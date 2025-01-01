const express = require('express');
const escape = require('escape-html');

const app = express();
app.get('/', (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));
