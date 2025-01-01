const express = require('express');
const escape = require('escape-html');
const app = express();
const PORT = process.env.PORT || 3000;

// Start the server
app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}`);
});

app.get('/boomtown', (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));

