const express = require("express");
const path = require("path");
const hbs = require("hbs");
const route = require("./routers/main");
const bodyParser = require("body-parser");
const mongoose = require("mongoose");
const session = require("express-session");
const MongoStore = require("connect-mongo");
const helmet = require("helmet");
const fileUpload = require('express-fileupload');
const { registerEntraRoutes } = require("./auth/entra");
require("./handlebar");

const app = express();
const isProduction = process.env.NODE_ENV === "production";
const mongoUrl = process.env.AZURE_COSMOS_CONNECTIONSTRING;
const sessionSecret = process.env.SESSION_SECRET;

if (!sessionSecret) {
    throw new Error("SESSION_SECRET must be supplied through Azure Key Vault or the local environment.");
}

app.set("trust proxy", 1);
app.use(helmet({
    contentSecurityPolicy: false,
    strictTransportSecurity: isProduction ? undefined : false
}));
app.use(fileUpload({
    limits: { fileSize: 5 * 1024 * 1024 },
    abortOnLimit: true,
    safeFileNames: true,
    preserveExtension: true
}));
app.use(session({
    name: "organic-ghee.sid",
    secret: sessionSecret,
    resave: false,
    saveUninitialized: false,
    store: mongoUrl ? MongoStore.create({
        mongoUrl,
        collectionName: "sessions",
        ttl: 60 * 60 * 8
    }) : undefined,
    cookie: {
        httpOnly: true,
        secure: isProduction,
        sameSite: "lax",
        maxAge: 1000 * 60 * 60 * 8
    }
}));
app.use(bodyParser.urlencoded({
    extended: true
}));

registerEntraRoutes(app);
app.get("/health", (req, res) => {
    const databaseReady = mongoose.connection.readyState === 1;
    res.status(databaseReady ? 200 : 503).json({
        status: databaseReady ? "healthy" : "degraded"
    });
});
app.use("", route);
//static folder
app.use("/static",express.static(path.join(__dirname, '..', 'public')));
//template engine
app.set("view engine",'hbs')
app.set("views",path.join(__dirname, '..', 'views'))
//app.set("views","")
hbs.registerPartials(path.join(__dirname, '..', 'views', 'partials'))





mongoose.connect(mongoUrl)
.then(() => {
    console.log("MongoDB Connected");
})
.catch((err) => {
    console.error("MongoDB connection error:", err.message);
})
const PORT = process.env.PORT || 5656;

app.listen(PORT, () => {
    console.log(`Server started on ${PORT}`);
});
