const axios = require('axios');

async function fetchData() {
  try {
    const response = await axios.get('https://api.example.com/data', { headers: { 'User-Agent': 'my-app' } });
    return response.data;
  } catch (error) {
    console.error(error);
    return null;
  }
}

module.exports = fetchData;
