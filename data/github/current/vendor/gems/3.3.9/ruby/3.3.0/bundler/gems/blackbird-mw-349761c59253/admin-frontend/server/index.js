const express = require("express");
const bodyParser = require("body-parser");

const { green, blue, yellow, red, orange, violet, cache001, cache002, cache003, cache004, zeta, theta, iota, eta, kappa, lambda, cache } = require("./data");

const PORT = process.env.PORT || 3001;

const app = express();
app.use(bodyParser.json());

const stamps = ["dotcom", "staff-wus2-01", "prod-weu-01", "prod-sdc-01", "prod-ae-01"];
const dotcomCorpora = [blue, green, yellow, red, orange, violet, cache001, cache002, cache003, cache004];
const proximaCorpora = [blue, green, cache001];
const assignments = {
  blue: zeta,
  green: eta,
  yellow: theta,
  red: iota,
  orange: kappa,
  violet: lambda,
  "cache-001": cache,
  "cache-002": cache,
  "cache-003": cache,
};

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/GetDeployAheadBehind", (req, res) => {
  const data = req.body;
  const statuses = data.commit_shas.map((sha, i) => {
    let pr;
    if (i === 0) {
      pr = {
        html_url: "https://github.com/github/blackbird/pull/7976",
        number: 7976,
        title: "blackbirdctl: Refactor indexing/ingest code.",
        author: "gorzell",
        ref: "gorzell/refactor-cli-ingest",
      };
    }
    return {
      commit_sha: sha,
      commits_behind: 1,
      pr: pr,
    }
  });
  res.json({ head_sha: "13240fd24fb480312e66adac4b8375c1a0727edb", statuses: statuses });
});


app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/ListStamps", (req, res) => {
  return res.json({ stamps: stamps });
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/GetCorpusStatus", (req, res) => {
  switch (req.headers["x-github-stamp"]) {
    case "dotcom":
      return res.json({ statuses: dotcomCorpora, deploy_env: "production" });
    default:
      return res.json({ statuses: proximaCorpora, deploy_env: req.headers["x-github-stamp"] });
  }
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/ShardAssignments", (req, res) => {
  setTimeout(() => {
    res.json(assignments[req.body.corpus]);
  }, 1000);
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/GetRepoStatus", (req, res) => {
  const data = req.body;
  if (data.repo_nwo === "github/github") {
    res.statusCode = 404;
    res.json({ code: "not_found", msg: "repo not found" });
  } else if (data.repo_nwo === "github/linguist") {
    // This one has a permanent failure
    res.json({
      repo_id: 1725199,
      repo_nwo: "github/linguist",
      is_public: true,
      serving_ingests: [],
      indexer_ingests: [],
      github_details: {
        error: null,
        repository: {
          id: 1725199,
          network_id: 1725199,
          owner_id: 9919,
          owner_login: "github",
          owner_spammy: false,
          name: "linguist",
          public: true,
          archived: false,
          disk_usage: 39275,
          pushed_at: "2023-03-27T14:02:45Z",
          created_at: "2011-05-09T22:53:13Z",
          license_name: "MIT License",
          num_watchers: 500,
          num_stars: 10836,
          has_readme: true,
          public_fork_count: 4000,
          paying_customer: true,
          experiments: { blackbird_enable_code_embedding: "1" },
          updated_at: "2023-03-27T14:02:45Z",
        },
      },
      database_repository: {
        repo_id: 1725199,
        owner_id: 9919,
        owner_login: "github",
        name: "linguist",
        public: true,
        source_topic: "blackbird.v0.BlackbirdBackfillBlue",
        deleted_at: null,
        is_archived: false,
        pushed_at: "2023-03-27T14:02:45Z",
        created_at: "2011-05-09T22:53:13Z",
        has_license: true,
        num_watchers: 500,
        num_stars: 10836,
        has_readme: true,
        public_fork_count: 4000,
        commit_seq_no: 5,
        commit_oid: "3123ffa0",
        network_id: 1725199,
        license_name: "MIT License",
        is_fork: false,
        experiments: { blackbird_enable_code_embedding: "1" },
        repo_seq_no: 11111,
      },
    });
  } else if (data.repo_nwo === "cdnjs/cdnjs") {
    // This one has a permanent failure in the indexer_ingests snapshot
    res.json({
      repo_id: 1409811,
      repo_nwo: "cdnjs/cdnjs",
      is_public: true,
      serving_ingests: [],
      indexer_ingests: [
        {
          corpus: "Blue",
          epoch_id: 4321,
          snapshot_entries: [
            {
              entry_id: "999123",
              head_oid: "feee8126ec6f78cdc8645f75fd4a98d41b482f94",
              repo_id: 1409811,
              owner_id: 123,
              network_id: 123,
              nwo: "cdnjs/cdnjs",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/master",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "1234576",
              permanent_error: "some other failure",
            },
          ],
        },
        {
          corpus: "Yellow",
          epoch_id: 4321,
          snapshot_entries: [
            {
              entry_id: "12345",
              head_oid: "feee8126ec6f78cdc8645f75fd4a98d41b482f94",
              repo_id: 1409811,
              owner_id: 123,
              network_id: 123,
              nwo: "cdnjs/cdnjs",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/master",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "80494460",
              permanent_error: "repository has too many blob/path locations",
            },
          ],
        },
      ],
      github_details: {
        error: null,
        repository: {
          id: 1409811,
          network_id: 123,
          owner_id: 123,
          owner_login: "cdnjs",
          owner_spammy: false,
          name: "cdnjs",
          public: true,
          archived: false,
          disk_usage: 123456,
          pushed_at: "2023-03-27T14:02:45Z",
          created_at: "2011-05-09T22:53:13Z",
          license_name: "MIT License",
          num_watchers: 500,
          num_stars: 10836,
          has_readme: true,
          public_fork_count: 4000,
          paying_customer: false,
          experiments: null,
          updated_at: "2023-03-27T14:02:45Z",
        },
      },
      database_repository: {
        repo_id: 1409811,
        owner_id: 123,
        owner_login: "cdnjs",
        name: "cdnjs",
        is_public: true,
        source_topic: "",
        deleted_at: null,
        is_archived: false,
        pushed_at: "2023-03-27T14:02:45Z",
        created_at: "2011-05-09T22:53:13Z",
        has_license: true,
        num_watchers: 500,
        num_stars: 10836,
        has_readme: true,
        public_fork_count: 4000,
        commit_seq_no: 9,
        commit_oid: "ffffffffeeeeeedddd",
        network_id: 123,
        license_name: "MIT License",
        is_fork: false,
        experiments: null,
        repo_seq_no: 0,
      },
    });
  } else if (data.repo_nwo === "iman-dev/mca") {
    res.json({
      repo_id: 540608826,
      repo_nwo: "iman-dev/mca",
      is_public: false,
      serving_ingests: [
        {
          corpus: "Blue",
          epoch_id: 312,
          snapshot_entries: [
            {
              entry_id: "1862617796",
              head_oid: "973e4a9367995746f71402752abf5307ee6ab196",
              repo_id: 540608826,
              owner_id: 123,
              network_id: 123,
              nwo: "iman-dev/mca",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "80494460",
            },
          ],
        },
        {
          corpus: "Green",
          epoch_id: 311,
          snapshot_entries: [
            {
              entry_id: "1776500723",
              head_oid: "973e4a9367995746f71402752abf5307ee6ab196",
              repo_id: 540608826,
              owner_id: 123,
              network_id: 123,
              nwo: "iman-dev/mca",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "33273634",
            },
          ],
        },
        {
          corpus: "Yellow",
          epoch_id: 309,
          snapshot_entries: [
            {
              entry_id: "1629650565",
              head_oid: "973e4a9367995746f71402752abf5307ee6ab196",
              repo_id: 540608826,
              owner_id: 123,
              network_id: 123,
              nwo: "iman-dev/mca",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "8736159",
            },
          ],
        },
      ],
      indexer_ingests: [
        {
          corpus: "Blue",
          epoch_id: 312,
          snapshot_entries: [
            {
              entry_id: "1862617796",
              head_oid: "973e4a9367995746f71402752abf5307ee6ab196",
              repo_id: 540608826,
              owner_id: 123,
              network_id: 123,
              nwo: "iman-dev/mca",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "80494460",
            },
          ],
        },
        {
          corpus: "Green",
          epoch_id: 311,
          snapshot_entries: [
            {
              entry_id: "1776500723",
              head_oid: "973e4a9367995746f71402752abf5307ee6ab196",
              repo_id: 540608826,
              owner_id: 123,
              network_id: 123,
              nwo: "iman-dev/mca",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "33273634",
            },
          ],
        },
        {
          corpus: "Yellow",
          epoch_id: 309,
          snapshot_entries: [
            {
              entry_id: "1629650565",
              head_oid: "973e4a9367995746f71402752abf5307ee6ab196",
              repo_id: 540608826,
              owner_id: 123,
              network_id: 123,
              nwo: "iman-dev/mca",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "8736159",
            },
          ],
        },
      ],
      github_details: {
        error: "",
        repository: {
          id: 540608826,
          network_id: 499461544,
          owner_id: 89855964,
          owner_login: "iman-dev",
          owner_spammy: false,
          name: "mca",
          public: false,
          archived: false,
          disk_usage: "857",
          pushed_at: "2022-09-23T20:35:32Z",
          created_at: "2022-09-23T20:35:29Z",
          license_name: "",
          num_watchers: 1,
          num_stars: 0,
          has_readme: true,
          public_fork_count: 0,
          paying_customer: true,
          experiments: { blackbird_enable_code_embedding: "1" },
          updated_at: "2022-09-23T20:35:32Z",
        },
      },
      deleted_at: null,
      database_repository: {
        repo_id: 540608826,
        owner_id: 89855964,
        owner_login: "iman-dev",
        name: "mca",
        is_public: false,
        source_topic: "",
        deleted_at: null,
        is_archived: false,
        pushed_at: "2022-09-23T20:35:32Z",
        created_at: "2022-09-23T20:35:29Z",
        has_license: false,
        num_watchers: 1,
        num_stars: 0,
        has_readme: true,
        public_fork_count: 0,
        commit_seq_no: 43,
        commit_oid: "cccceee11123490aafed",
        network_id: 499461544,
        license_name: "",
        is_fork: false,
        experiments: { blackbird_enable_code_embedding: "1" },
        repo_seq_no: 9999,
      },
    });
  } else if (data.repo_nwo === "github_iaharvqc/octoshift") {
    // This repo is not known to blackbird yet.
    res.json({
      repo_id: 2211821,
      repo_nwo: "github_iaharvqc/octoshift",
      is_public: false,
      serving_ingests: [],
      indexer_ingests: [],
      github_details: {
        error: "",
        repository: {
          id: 2211821,
          network_id: 2189201,
          owner_id: 122941,
          owner_login: "github_iaharvqc",
          owner_spammy: false,
          name: "octoshift",
          public: false,
          archived: false,
          disk_usage: "287779",
          pushed_at: "2023-12-15T00:29:35Z",
          created_at: "2023-08-07T21:04:53Z",
          license_name: "",
          num_watchers: 1,
          num_stars: 4,
          has_readme: false,
          public_fork_count: 0,
          paying_customer: true,
          experiments: null,
          updated_at: "2023-12-15T00:29:35Z",
        },
      },
      deleted_at: null,
      database_repository: {
        repo_id: 2211821,
        owner_id: 122941,
        owner_login: "github_iaharvqc",
        name: "octoshift",
        is_public: false,
        source_topic: "",
        deleted_at: null,
        is_archived: false,
        pushed_at: "2023-12-15T00:29:35Z",
        created_at: "2023-08-07T21:04:53Z",
        has_license: false,
        num_watchers: 1,
        num_stars: 4,
        has_readme: false,
        public_fork_count: 0,
        commit_seq_no: 92,
        commit_oid: "9a2da071746ffcc4102dce01b4826aeb3e97840d",
        network_id: 2189201,
        license_name: "",
        is_fork: false,
        experiments: null,
        repo_seq_no: 3,
      },
    });
  } else {
    res.json({
      repo_id: 253831084,
      repo_nwo: "github/blackbird",
      is_public: false,
      serving_ingests: [],
      indexer_ingests: [
        {
          corpus: "Blue",
          epoch_id: 267,
          snapshot_entries: [
            {
              entry_id: "448532221",
              head_oid: "6d6797297926311c1a6e5147ee91ee9f33c2926b",
              repo_id: 253831084,
              owner_id: 9190,
              network_id: 1234,
              nwo: "github/blackbird",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "173336900",
            },
          ],
        },
        {
          corpus: "Green",
          epoch_id: 268,
          snapshot_entries: [
            {
              entry_id: "448532216",
              head_oid: "6d6797297926311c1a6e5147ee91ee9f33c2926b",
              repo_id: 253831084,
              owner_id: 9190,
              network_id: 1234,
              nwo: "github/blackbird",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "135907175",
            },
          ],
        },
        {
          corpus: "Yellow",
          epoch_id: 270,
          snapshot_entries: [
            {
              entry_id: "445892942",
              head_oid: "6d6797297926311c1a6e5147ee91ee9f33c2926b",
              repo_id: 253831084,
              owner_id: 9190,
              network_id: 1234,
              nwo: "github/blackbird",
              is_repo_public: false,
              is_repo_archived: false,
              repo_score: -3500,
              ref_name: "refs/heads/main",
              entry_state: "SNAPSHOT_ENTRY_STATE_ACTIVE",
              serving_offset: "7037720",
            },
          ],
        },
      ],
      github_details: {
        error: "",
        repository: {
          id: 253831084,
          network_id: 264983364,
          owner_id: 9919,
          owner_login: "github",
          owner_spammy: false,
          name: "blackbird",
          public: false,
          archived: false,
          disk_usage: "34618",
          pushed_at: "2023-03-15T16:32:48Z",
          created_at: "2020-04-07T15:14:03Z",
          license_name: "",
          num_watchers: 138,
          num_stars: 7,
          has_readme: true,
          public_fork_count: 0,
          paying_customer: true,
          experiments: { blackbird_enable_code_embedding: "1" },
          updated_at: "2023-03-15T16:32:48Z",
        },
      },
      database_repository: {
        repo_id: 253831084,
        owner_id: 9919,
        owner_login: "github",
        name: "blackbird",
        is_public: false,
        source_topic: "cp1-iad.ingest.github.search.v0.RepositoryChanged",
        deleted_at: null,
        is_archived: false,
        pushed_at: "2023-03-15T16:32:48Z",
        created_at: "2020-04-07T15:14:03Z",
        has_license: false,
        num_watchers: 138,
        num_stars: 7,
        has_readme: true,
        public_fork_count: 0,
        commit_seq_no: 11,
        commit_oid: "deadbeef00000123",
        network_id: 264983364,
        license_name: "",
        is_fork: false,
        experiments: { blackbird_enable_code_embedding: "1" },
        repo_seq_no: 123456,
      },
    });
  }
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/ProbeRepo", (req, res) => {
  res.json({
    verified: 368,
    missing: ["example/missing/path"],
    extra: ["example/extra"],
    num_trailing_zeros: 0,
  });
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/ClusterHosts", (req, res) => {
  let out = [];
  switch (req.body.corpus) {
    case "blue":
      out = zeta["host_assignments"].map((item) => item["hostname"]);
      break;
    case "green":
      out = eta["host_assignments"].map((item) => item["hostname"]).slice(0, 32);
      break;
    case "yellow":
    case "red":
    case "orange":
    case "violet":
      out = theta["host_assignments"].map((item) => item["hostname"]).concat("blackbird-index-not-in-dsa-1.azure-eastus.github.net", "blackbird-index-not-in-dsa-2.azure-eastus.github.net");
      break;
    default:
      break;
  }

  res.json({ hosts: out });
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/SetServingCorpus", (req, res) => {
  console.log(req.path, req.body);
  const corpus = req.body.corpus.toLowerCase();
  dotcomCorpora.forEach((c) => {
    if (c.corpus_name.toLowerCase() === corpus) {
      c.serving = true;
    } else {
      c.serving = false;
    }
  });

  res.json({});
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusQueryState", (req, res) => {
  console.log(req.path, req.body);
  const corpus = req.body.corpus.toLowerCase();

  let anotherServing = false;
  dotcomCorpora.forEach((c) => {
    if (c.corpus_name.toLowerCase() !== corpus && c.serving) {
      anotherServing = true;
    }
  });

  if (!req.body.serving && !anotherServing && !req.body.force) {
    console.log("must have at least one serving corpus.");
    res.status(400).json({ msg: "must have at least one serving corpus." });
    return;
  }

  let c = dotcomCorpora.find((c) => c.corpus_name.toLowerCase() === corpus);
  if (c !== undefined) {
    c.serving = req.body.serving;
    console.log(c);
  }
  res.json({});
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusShadowTraffic", (req, res) => {
  console.log(req.path, req.body);
  const corpus = req.body.corpus.toLowerCase();
  dotcomCorpora.forEach((c) => {
    if (c.corpus_name.toLowerCase() === corpus) {
      c.shadow_traffic_percent = req.body.percent;
    }
  });

  res.json({});
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/BranchEpoch", (req, res) => {
  console.log(req.path, req.body);
  res.json({});
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/IndexRepoList", (req, res) => {
  console.log(req.path, req.body);
  res.json({});
});

app.post(
  [
    "/twirp/blackbirdmw.admin.v1.AdminAPI/IndexRepo",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/ResetRateLimitQuota",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/ChangeEpoch",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusIndexingState",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusHealingState",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/PinCorpus",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/UnpinCorpus",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusCacheCluster",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetEpochDescription",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/BeginBackfillCorpus",
  ],
  (req, res) => {
    console.log(req.body);
    res.json({});
  }
);

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/GetRateLimitQuota", (req, res) => {
  res.json({
    quotas: [
      {
        type: "user-query",
        short_term_rate: 0,
        long_term_rate: 0.034823202219798,
        banned_seconds: 0,
      },
      {
        type: "find-definitions",
        short_term_rate: 0,
        long_term_rate: 0.00050644106713078,
        banned_seconds: 0,
      },
      {
        type: "find-references",
        short_term_rate: 0,
        long_term_rate: 0.009464224825919,
        banned_seconds: 0,
      },
      {
        type: "suggest",
        short_term_rate: 0,
        long_term_rate: 0.081817542657132,
        banned_seconds: 0,
      },
      {
        type: "count",
        short_term_rate: 0,
        long_term_rate: 0.012858610548614,
        banned_seconds: 0,
      },
    ],
  });
});

app.listen(PORT, () => {
  console.log(`Server listening on ${PORT}`);
});
