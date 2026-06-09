const crypto = require("crypto");
const msal = require("@azure/msal-node");

function getEntraConfig() {
    const tenantId = process.env.ENTRA_TENANT_ID;
    const clientId = process.env.ENTRA_CLIENT_ID;
    const clientSecret = process.env.ENTRA_CLIENT_SECRET;
    const redirectUri = process.env.ENTRA_REDIRECT_URI;

    if (!tenantId || !clientId || !clientSecret || !redirectUri) {
        return null;
    }

    return {
        tenantId,
        clientId,
        redirectUri,
        adminRole: process.env.ENTRA_ADMIN_ROLE || "Admin",
        authority: `https://login.microsoftonline.com/${tenantId}`,
        postLogoutRedirectUri: process.env.ENTRA_POST_LOGOUT_REDIRECT_URI || redirectUri.replace("/auth/entra/callback", "/")
    };
}

function createClient(config) {
    return new msal.ConfidentialClientApplication({
        auth: {
            clientId: config.clientId,
            authority: config.authority,
            clientSecret: process.env.ENTRA_CLIENT_SECRET
        },
        system: {
            loggerOptions: {
                piiLoggingEnabled: false,
                logLevel: msal.LogLevel.Warning
            }
        }
    });
}

function registerEntraRoutes(app) {
    app.get("/auth/admin/login", async (req, res, next) => {
        try {
            const config = getEntraConfig();
            if (!config) {
                return res.status(503).send("Microsoft Entra ID authentication is not configured.");
            }

            const state = crypto.randomBytes(32).toString("hex");
            const nonce = crypto.randomBytes(32).toString("hex");
            req.session.entraAuth = { state, nonce };

            const url = await createClient(config).getAuthCodeUrl({
                scopes: ["openid", "profile", "email"],
                redirectUri: config.redirectUri,
                state,
                nonce,
                prompt: "select_account"
            });
            return res.redirect(url);
        } catch (error) {
            return next(error);
        }
    });

    app.get("/auth/entra/callback", async (req, res, next) => {
        try {
            const config = getEntraConfig();
            const pending = req.session.entraAuth;
            if (!config || !pending || req.query.state !== pending.state || !req.query.code) {
                return res.status(400).send("Invalid Microsoft Entra ID authentication response.");
            }

            const result = await createClient(config).acquireTokenByCode({
                code: req.query.code,
                scopes: ["openid", "profile", "email"],
                redirectUri: config.redirectUri,
                nonce: pending.nonce
            });

            const claims = result.idTokenClaims || {};
            const roles = Array.isArray(claims.roles) ? claims.roles : [];
            if (!roles.includes(config.adminRole)) {
                req.session.destroy(() => {});
                return res.status(403).send("Your Microsoft Entra ID account is not assigned the application administrator role.");
            }

            await new Promise((resolve, reject) => {
                req.session.regenerate((error) => error ? reject(error) : resolve());
            });

            req.session.admin = {
                objectId: claims.oid,
                tenantId: claims.tid,
                name: claims.name || result.account?.name || "Administrator",
                username: claims.preferred_username || result.account?.username,
                roles
            };
            req.session.loginUser = {
                name: req.session.admin.name,
                email: req.session.admin.username,
                type: "admin",
                entra: true
            };

            return res.redirect("/dashboard");
        } catch (error) {
            return next(error);
        }
    });

    app.get("/auth/admin/logout", (req, res) => {
        const config = getEntraConfig();
        const logoutUrl = config
            ? `${config.authority}/oauth2/v2.0/logout?post_logout_redirect_uri=${encodeURIComponent(config.postLogoutRedirectUri)}`
            : "/";

        req.session.destroy(() => res.redirect(logoutUrl));
    });
}

module.exports = { registerEntraRoutes };
