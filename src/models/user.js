const mongoose = require("mongoose");

const User = mongoose.Schema({
    name: { type: String, required: true, trim: true },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    phone: { type: String, trim: true },
    password: { type: String, required: true, select: false },
    address: { type: String, trim: true },
    type: { type: String, enum: ["normal"], default: "normal", immutable: true }
}, {
    timestamps: true
});

module.exports = mongoose.model("user", User);
