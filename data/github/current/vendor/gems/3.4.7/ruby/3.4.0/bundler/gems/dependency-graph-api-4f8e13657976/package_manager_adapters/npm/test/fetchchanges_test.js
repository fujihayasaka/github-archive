const fetchChanges = require('../lib/fetchchanges')
const expect = require('expect.js')
const Server = require('./fake_replicate_npm')
const server = new Server({port: 5557})

describe('fetching changes from npm', () => {
  before(() => server.start())
  beforeEach(() => server.reset())

  it('fetches changes from npm', async () => {
    const data1 = [
      {"seq":1,"id":"jquery","changes":[{"rev":"61-29253bcc4c2e86cf5722a540fa50c076"}]},
      {"seq":2,"id":"lodash","changes":[{"rev":"62-39253bcc4c2e86cf5722a540fa50c076"}]},
      {"seq":3,"id":"express","changes":[{"rev":"63-49253bcc4c2e86cf5722a540fa50c076"}]}
    ]
    server.addResult(0, data1)
    const data2 = [
      {"seq":4,"id":"react","changes":[{"rev":"64-59253bcc4c2e86cf5722a540fa50c076"}]},
      {"seq":5,"id":"angular","changes":[{"rev":"65-69253bcc4c2e86cf5722a540fa50c076"}]}
    ]
    server.addResult(3, data2)
    const response = await fetchChanges('http://localhost:5557/registry/_changes', 0)
    expect(response.results).to.eql(data1)
    expect(response.last_seq).to.equal(3)
    const response2 = await fetchChanges('http://localhost:5557/registry/_changes', 3)
    expect(response2.results).to.eql(data2)
    expect(response2.last_seq).to.equal(5)
  })
})
