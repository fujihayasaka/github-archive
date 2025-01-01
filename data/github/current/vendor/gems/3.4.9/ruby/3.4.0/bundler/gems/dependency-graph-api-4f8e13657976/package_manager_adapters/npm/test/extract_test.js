const fetchChanges = require("../lib/fetchchanges");
const expect = require("expect.js");
const NPMServer = require("./fake_replicate_npm");
const SinkServer = require("./fake_http_sink");
const Checkpoint = require("../lib/checkpoint");
const extract = require("../lib/extract");

const sinkServer = new SinkServer({ port: 5558 });
const npmServer = new NPMServer({ port: 5559 });

const sinkProxyUrl = "http://localhost:5558";
const npmRegistryUrl = "http://localhost:5559/";
const npmUrl = "http://localhost:5559/registry/_changes";

describe("fetching changes from npm", () => {
  before(() => {
    npmServer.start();
    sinkServer.start();
  });

  beforeEach(() => {
    npmServer.reset();
    sinkServer.reset();
  });

  it("processes end to end", async () => {
    const checkpoint = new Checkpoint(sinkProxyUrl);
    let since = 0;
    await checkpoint.set(since);
    const data1 = [
      {
        seq: 1,
        id: "jquery",
        changes: [{ rev: "61-29253bcc4c2e86cf5722a540fa50c076" }],
      },
      {
        seq: 2,
        id: "lodash",
        changes: [{ rev: "62-39253bcc4c2e86cf5722a540fa50c076" }],
      },
      {
        seq: 3,
        id: "express",
        changes: [{ rev: "63-49253bcc4c2e86cf5722a540fa50c076" }],
      },
    ];
    npmServer.addResult(0, data1);
    await extract(npmUrl, sinkProxyUrl, npmRegistryUrl);
    since = await checkpoint.get();
    expect(since).to.equal(3);
    await sinkServer.waitForPackageReleases(3);

    // There are two versions of each package in the test data
    expect(sinkServer.packageReleases.length).to.equal(6);
    const packageNames = sinkServer.packageReleases.map(
      (pkg) => pkg.package_name
    );
    expect(packageNames).to.eql(["jquery", "jquery", "lodash", "lodash", "express", "express"]);
  });
});
