const undici = require('undici')
const log = require('./logger')
const UserAgent = 'Github Dependency Graph NPM PMA'

module.exports = async function fetchChanges (url, checkpoint) {
  const urlObj = new URL(url);
  if (checkpoint !== undefined) {
    urlObj.searchParams.set('since', checkpoint);
  }

  const {
    statusCode,
    headers,
    body
  } = await undici.request(urlObj, {
    method: 'GET',
    headers: {
      'User-Agent': UserAgent,
      'npm-replication-opt-in': 'true'
    },
    maxRedirections: 5
  })
  if (statusCode === 200) {
    const data = await body.json();
    return data;

  } else if (statusCode === 429) {
    // Retry after the specified number of seconds
    const retryAfter = headers.get('Retry-After');
    log(`Rate limited by npmjs.com. Retrying after ${retryAfter} seconds`);
    await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
    return fetchChanges(url, checkpoint);

  } else if (statusCode === 404) {
    throw new Error(`Checkpoint ${checkpoint} not found`);

  }
  throw new Error(`Request failed with status: ${statusCode}`);
}
