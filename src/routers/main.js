const { Router } = require('express');
const express = require('express');
const mongoose = require("mongoose");
const bcrypt = require("bcrypt");
const route = express.Router();
const User = require('../models/user')
const dish = require("../models/dish");
const order = require('../models/order')
const { requireAdmin, requireCustomer, requireDashboardAccess } = require("../middleware/auth");
const { deleteDishImage, uploadDishImage } = require("../services/blob-storage");
const { enqueueNotification } = require("../services/notifications");

route.get("/", (req, res) => {
    const loginUser = req.session.loginUser;
    res.render("index", {
        loginUser: loginUser
    })
})
route.get("/register", (req, res) => {
    const loginUser = req.session.loginUser;
    res.render("registration", {
        loginUser: loginUser
    })
})
route.get('/login', (req, res) => {
    const loginUser = req.session.loginUser;
    res.render("login", {
        loginUser: loginUser
    })
})
//food page normal user
route.get("/foods/:page", async (req, res) => {
    const loginUser = req.session.loginUser;
    let currentPage = 1;
    let page = req.params.page;
    if (page)
        currentPage = page;
    const total = 6;
    const start = (currentPage - 1) * total;
    const foods = await dish.find().skip(start).limit(total);
    const count = Math.ceil(await dish.find().countDocuments() / total);

    console.log(count + " :=> " + foods);
    res.render("showDishes", {
        loginUser: loginUser,
        foods: foods,
        count: count,
        currentPage: currentPage

    })
})
route.post("/saveRegistration", async (req, res) => {
    const password = await bcrypt.hash(req.body.password, 12);
    await User.create({
        name: req.body.name,
        email: req.body.email,
        phone: req.body.phone,
        password,
        address: req.body.address,
        type: "normal"
    });
    res.render("login", {
        newRegister: true
    });
})

route.post("/loginUser", async (req, res) => {
    const email = String(req.body.email || "").trim().toLowerCase();
    const data = await User.findOne({ email, type: "normal" }).select("+password");
    const passwordValid = data && await bcrypt.compare(req.body.password || "", data.password);

    if (!passwordValid) {
        console.log("invalid passward or email");
        res.render("login", {
            invalid: true,
            email
        })
    }
    else {
        req.session.regenerate((error) => {
            if (error) {
                return res.status(500).send("Unable to create a secure session.");
            }
            req.session.loginUser = {
                _id: data._id.toString(),
                name: data.name,
                email: data.email,
                type: "normal"
            };
            return res.redirect("/dashboard");
        });
    }
})

route.get("/dashboard", requireDashboardAccess, (req, res) => {
    const loginUser = req.session.loginUser;
    const view = loginUser.type === "admin"
        ? "adminDashboard"
        : "userPages/userDashboard";

    return res.render(view, { loginUser });
})

route.use("/admin", requireAdmin);

route.get("/admin/addDish", (req, res) => {
    if (req.session.loginUser) {
        const loginUser = req.session.loginUser;

        if (loginUser.type == "admin") {
            res.render("addNewDish", {
                loginUser: loginUser
            })
        } else {
            res.send(`<h1>Something Wrong !!</h1> <h2>Opps! you can not acess this page..</h2>`)
        }
    } else
        res.render("login", {
            loginFirst: true
        })
})

//this get method for show food table in admin pannel
route.get("/admin/dishMenus/:page", async function (req, res) {
    if (req.session.loginUser) {
        const loginUser = req.session.loginUser;
        let currentPage = 1;
        let page = req.params.page;
        if (page)
            currentPage = page;
        const total = 6;
        const start = (currentPage - 1) * total;
        const data = await dish.find().skip(start).limit(total);
        const newObject = Object.assign({}, data, { currentPage: currentPage })
        const totalPage = Math.ceil(await dish.find().countDocuments() / total)
        if (loginUser.type == "admin") {
            res.render("adminFoodTable", {
                loginUser: loginUser,
                foods: data,
                currentPage: currentPage,
                count: totalPage
            })
        } else {
            res.send(`<h1>Something Wrong !!</h1> <h2>Opps! you can not acess this page..</h2> `)
        }
    } else
        res.render("login", {
            loginFirst: true
        })
})

//search food dish by user
route.post("/searchFood", async (req, res) => {
    const loginUser = req.session.loginUser;
    const search = req.body.foodSearch
    const data = await dish.find({ "dname": new RegExp(search, 'i') });
    res.render("showDishes", {
        loginUser: loginUser,
        foods: data,
        searchKey: search
    })
})

//save dish here
route.post('/saveDish', requireAdmin, async (req, res) => {


    if (req.files == null || req.body.ddiscount > 100 || req.body.dname == '' || req.body.dprice <= 0) {
        res.render("addNewDish", {
            notsave: true
        })
        return;
    }
    const { photo } = req.files;
    const image = await uploadDishImage(photo);
    req.body.photo = image.name;
    req.body.photoUrl = image.url;
    const data = await dish.create(req.body)

    if (data) {
        console.log("dish save")
        res.render("addNewDish", {
            save: true
        })
    } else {
        console.log("dish not save")
        res.render("addNewDish", {
            notsave: true
        })
    }
})

//delete the dish
route.get('/admin/deleteDish/:id', async (req, res) => {
    if (req.session.loginUser) {
        const loginUser = req.session.loginUser
        const existingDish = await dish.findById(req.params.id);
        const data = await dish.deleteOne({ "_id": req.params.id })
        if (data) {
            await deleteDishImage(existingDish?.photo);
            console.log("file is deleted...")

            currentPage = 1;
            const total = 6
            const start = (currentPage - 1) * total
            const foods = await dish.find().skip(start).limit(total)
            const totalPage = Math.ceil(await dish.find().countDocuments() / total)
            res.render("adminFoodTable", {
                loginUser: loginUser,
                foods: foods,
                currentPage: 1,
                count: totalPage,
                delete: true
            })
        } else {
            res.send("<h1>Server Error !!</h1><h2> Soory dish is not deleted p;ease try letter..</br><a href='/admin/dishMenus/1'>Back to dish menu table</a> </h2>")
        }
    } else
        res.render("login", {
            loginFirst: true
        })

})
//place order
route.get("/admin/adminOrder/:page", async (req, res) => {
    if (req.session.loginUser) {
        const loginUser = req.session.loginUser;
        if (loginUser.type == 'admin') {
            let currentPage = 1;
            const page = req.params.page;
            if (page)
                currentPage = page;
            const total = 10;
            const start = (currentPage - 1) * total;
            const data = await order.find().skip(start).limit(total);
            const totalPage = Math.ceil(order.find().countDocuments() / total);
            console.log("place order" + data)
            res.render('adminOrders', {
                loginuser: loginUser,
                orders: data,
                currentPage: currentPage,
                count: totalPage
            })

        }
    } else {
        res.render("login", {
            loginFirst: true
        })
    }
})

//change order states
route.get("/admin/cooking/:id", async (req, res) => {
    if (req.session.loginUser) {
        if (req.session.loginUser.type == 'admin') {
            
            const data = await order.updateOne({ _id: req.params.id }, { $set: { states: "Cooking" } })
            res.redirect("/admin/adminOrder/1")
        }else
        res.send("<h2>Wrong page try to access...</h2>")
    } else {
        res.render("login", {
            loginFirst: true
        })
    }
})
route.get("/admin/deliver/:id", async (req, res) => {
    if (req.session.loginUser) {
        if (req.session.loginUser.type == 'admin') {
        
            const data = await order.updateOne({ _id: req.params.id }, { $set: { states: "Out for deliver." } })
            
            res.redirect("/admin/adminOrder/1")
        }else
        res.send("<h2>Wrong page try to access...</h2>")
    } else {
        res.render("login", {
            loginFirst: true
        })
    }
})
route.get("/admin/handover/:id", async (req, res) => {
    if (req.session.loginUser) {
        if (req.session.loginUser.type == 'admin') {
            console.log("function i scalled")
            const data = await order.updateOne({ _id: req.params.id }, { $set: { states: "Order completed." } })
    
            res.redirect("/admin/adminOrder/1")
        }else
        res.send("<h2>Wrong page try to access...</h2>")
    } else {
        res.render("login", {
            loginFirst: true
        })
    }
})

//edit dish here
route.get("/admin/editDish/:id/:flag", async (req, res) => {
    if (req.session.loginUser) {
        const loginUser = req.session.loginUser
        if (loginUser.type == 'admin') {
            const data = await dish.findById(req.params.id)
            const flag = req.params.flag
            if (data) {
                res.render("adminEditDish", {
                    food: data,
                    loginUser: loginUser
                })
            } else {
                res.send(`<h1>Something Wrong !!</h1> <h2>Opps! Dish not Found...</h2> `)

            }

        } else {
            res.send(`<h1>Something Wrong !!</h1> <h2>Opps! you can not acess this page..</h2> `)
        }
    } else
        res.render("login", {
            loginFirst: true
        })
})

route.post("/admin/saveEditDish/:id", async (req, res) => {

    if (req.session.loginUser) {

        if (req.files == null)
            console.log("photo not selected")
        else {
            await deleteDishImage(req.body.tempImage);
            const { photo } = req.files
            const image = await uploadDishImage(photo);
            req.body.photo = image.name;
            req.body.photoUrl = image.url;
        }

        const data = await dish.updateOne({ _id: req.params.id }, { $set: req.body })
        if (data) {
            console.log("dish updated")
            res.redirect("/admin/editDish/" + req.params.id + "/success")
        } else {
            console.log('dish not updated')
            res.redirect("/admin/editDish/" + req.params.id + "/error")

        }
    } else
        res.render("login", {
            loginFirst: true
        })
})
route.get("/logout", (req, res) => {
    if (req.session.admin) {
        return res.redirect("/auth/admin/logout");
    }
    req.session.destroy();
    res.render("login", {
        logout: true
    })
})

route.post("/contact", async (req, res) => {
    await enqueueNotification({
        type: "contact",
        name: req.body.name,
        email: req.body.email,
        subject: req.body.subject,
        message: req.body.message
    });
    return res.redirect("/?contact=sent");
});

//check out
route.get("/user/orderFood", requireCustomer, (req, res) => {
    if (req.session.loginUser) {
        const loginUser = req.session.loginUser
        res.render("userPages/userCheckout", {
            loginUser: loginUser
        })
    } else {
        res.render("login", {
            loginFirst: true
        })
    }
})

route.post("/orderNowFromBasket", requireCustomer, (req, res) => {
    if (req.session.loginUser) {
        res.redirect("/")
        const loginUser = req.session.loginUser;
        const basket = JSON.parse(req.body.data)
        let dt_ob = new Date();
        let dateTime = "" + ("0" + dt_ob.getDate()).slice(-2) + "/" + ("0" + dt_ob.getMonth()).slice(-2) + "/" + dt_ob.getFullYear() + " T " + dt_ob.getHours() + ":" + dt_ob.getMinutes() + ":" + dt_ob.getSeconds();
        const paymentType = req.body.paymentType

        basket.forEach(async function (item) {
            let object = {
                dishId: item.id,
                userId: loginUser._id,
                user: loginUser,
                photo: item.image,
                dname: item.name,
                time: dateTime,
                price: item.price,
                quantity: item.quantity,
                paymentType: paymentType,
                states: "NA"//not active order
            }
            console.log(object)
            const data = await order.create(object);
            if (data) {
                await enqueueNotification({
                    type: "order-confirmation",
                    recipient: loginUser.email,
                    customerName: loginUser.name,
                    orderId: data._id.toString(),
                    dishName: item.name,
                    quantity: item.quantity,
                    price: item.price
                });
            }

        });
    } else {
        res.render("login", {
            loginFirst: true
        })
    }
})

//order page
route.get("/user/orders", requireCustomer, async (req, res) => {
    if (req.session.loginUser) {
        const loginUser = req.session.loginUser;
        const data = await order.find({ $and: [{ "states": { $ne: "deliverd" } }, { "userId": req.session.loginUser._id }] });
        console.log("find data : " + data)
        res.render("userPages/userOrders", {
            loginUser: loginUser,
            orderFood: data
        })
    } else {
        res.render("login", {
            loginFirst: true
        })
    }
})

route.get("/user/cancelOrder/:id", requireCustomer, async (req, res) => {
    const loginUser = req.session.loginUser;
    const customerId = loginUser._id;

    if (!mongoose.isObjectIdOrHexString(req.params.id)) {
        return res.status(404).send("Order not found.");
    }

    const deleteResult = await order.deleteOne({
        _id: req.params.id,
        userId: customerId
    });

    if (deleteResult.deletedCount !== 1) {
        return res.status(404).send("Order not found.");
    }

    const data = await order.find({
        states: { $ne: "deliverd" },
        userId: customerId
    });

    return res.render("userPages/userOrders", {
        loginUser,
        orderFood: data,
        cancelOrder: true
    });
})

route.get("/user/history", requireCustomer, async (req, res) => {
    if (req.session.loginUser) {

        const loginUser = req.session.loginUser;
        const data = await order.find({ "userId": req.session.loginUser._id });


        res.render("userPages/userHistory", {
            loginUser: loginUser,
            history: data
        })
    } else {
        res.render("login", {
            loginFirst: true
        })
    }
})

module.exports = route
