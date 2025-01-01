const undici = require('undici')
const log = require('./logger')
const checkpointName = 'npm_couch'

module.exports = class Checkpoint {
  constructor (sink_proxy_url) {
    this.url = `${sink_proxy_url}/checkpoints/${checkpointName}`
  }

  get () {
    return undici.fetch(this.url)
      .then(response => response.json())
      .then(data => {
        const n = parseInt(data.value);
        if (isNaN(n)) throw new Error(`'${n}' is not a number!`)
        return n
      });
  }

  set (n) {
    if (isNaN(parseInt(n))) throw new Error(`'${n}' is not a number!`)
    log(`Setting checkpoint ${checkpointName} to ${n}`)

    return undici.fetch(this.url, {
      method: "PUT",
      body: new URLSearchParams({
        value: n
      })
    })
  }
}
