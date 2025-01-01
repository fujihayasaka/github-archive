const express = require('express');
const path = require('path');
const escape2 = require('escape-html');
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware to parse request body
app.use(express.urlencoded({ extended: true }));

// Serve static files from the 'public' directory
app.use(express.static(path.join(__dirname, 'public')));

// In-memory array to store tasks
let tasks = [];

// Route to serve the homepage (a simple HTML form for the to-do list)
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Route to handle adding tasks
app.post('/add-task', (req, res) => {
  const { taskDescription } = req.body;
  if (taskDescription) {
    tasks.push({ description: taskDescription, done: false });
  }
  res.redirect('/');
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}`);
});

app.get('/boomcity', (req, res) => res.send(`Hello, ${escape2(req.query.name)}!`));

