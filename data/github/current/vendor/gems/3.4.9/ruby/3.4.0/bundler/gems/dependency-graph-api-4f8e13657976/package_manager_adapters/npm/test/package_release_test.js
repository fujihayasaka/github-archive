const path = require('path')
const expect = require('expect.js')
const root = path.join(__dirname, '/../')
const stubs = require('./stub_data')
const testsWithLicense = stubs.testReleasesWithLicense
const testsWithLicenses = stubs.testReleasesWithLicenses

describe('PackageRelease', () => {
  it('parses release-level license clauses', () => {
    testsWithLicense.forEach((t, i) => {
      expect(t.release.license).to.equal(t.expected);
    });
  })

  it('parses release-level licenses clauses', () => {
    testsWithLicenses.forEach((t, i) => {
      expect(t.release.license).to.equal(t.expected);
    });
  })
})
