function requireCustomer(req, res, next) {
    if (req.session?.loginUser?.type === "normal") {
        return next();
    }
    return res.status(401).render("login", { loginFirst: true });
}

function requireAdmin(req, res, next) {
    if (req.session?.admin && req.session?.loginUser?.type === "admin") {
        return next();
    }
    return res.redirect("/auth/admin/login");
}

function requireDashboardAccess(req, res, next) {
    if (req.session?.loginUser?.type === "normal") {
        return requireCustomer(req, res, next);
    }
    return requireAdmin(req, res, next);
}

module.exports = { requireAdmin, requireCustomer, requireDashboardAccess };
