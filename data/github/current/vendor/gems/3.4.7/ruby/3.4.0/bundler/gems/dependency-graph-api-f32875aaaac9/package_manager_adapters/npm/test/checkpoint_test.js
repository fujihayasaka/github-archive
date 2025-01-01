const path = require('path')
const root = path.join(__dirname, '/../')
const expect = require('expect.js')
const Checkpoint = require(path.join(root, 'lib/checkpoint'))
const Server = require('./fake_http_sink')
const server = new Server({port: 5556})

describe('checkpointing', () => {
  before(() => server.start())
  beforeEach(() => server.reset())

  it('supports persistent setting and getting', (done) => {
    let checkpoint = new Checkpoint('http://localhost:5556')
    checkpoint.get()
      .then((val) => expect(val).to.equal(0))
      .then(() => checkpoint.set(10))
      .then(() => checkpoint.get())
      .then((val) => expect(val).to.equal(10))
      .then(() => {
        checkpoint = new Checkpoint('http://localhost:5556')
        checkpoint.get()
          .then((val) => expect(val).to.equal(10))
          .catch(done)
      })
      .finally(done)
  })
})
