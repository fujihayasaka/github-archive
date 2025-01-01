const path = require('path')
const root = path.join(__dirname, '/../')
const expect = require('expect.js')
const Checkpoint = require(path.join(root, 'lib/checkpoint'))
const Server = require('./fake_http_sink')
const server = new Server({port: 5556})

describe('checkpointing', () => {
  before(() => server.start())
  beforeEach(() => server.reset())

  it('supports persistent setting and getting', async () => {
    let checkpoint = new Checkpoint('http://localhost:5556')
    let val = await checkpoint.get()
    expect(val).to.equal(0)
    await checkpoint.set(10)
    val = await checkpoint.get()
    expect(val).to.equal(10)
    checkpoint = new Checkpoint('http://localhost:5556')
    val = await checkpoint.get()
    expect(val).to.equal(10)
  })
})
