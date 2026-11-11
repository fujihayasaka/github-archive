import express from "express";
import bodyParser from "body-parser";

import { repoStatus, } from "./data.js";

import dotcom from "./data/dotcom.json" with { type: "json" };
import proxima from "./data/staff-wus2-01.json" with { type: "json" };

function getDb(req) {
  if (req.headers["x-github-stamp"] === "dotcom") {
    return dotcom;
  } else {
    return proxima;
  }
}

const PORT = process.env.PORT || 3001;

const app = express();
app.use(bodyParser.json());
app.use((req, res, next) => {
  if (!/(ListStamps|GetCorpusStatus|ShardAssignments|ClusterHosts)$/.test(req.path)) {
    console.log("[%s] %s %o", req.headers["x-github-stamp"], req.path, req.body);
  }
  next();
});

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
    };
  });
  res.json({ head_sha: "13240fd24fb480312e66adac4b8375c1a0727edb", statuses: statuses });
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/ListStamps", (req, res) => {
  return res.json({ stamps: dotcom.stamps, localDev: true });
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/GetCorpusStatus", (req, res) => {
  return res.json(getDb(req).corpora);
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/ShardAssignments", (req, res) => {
  const corpus = req.body.corpus.toLowerCase();
  setTimeout(() => {
    return res.json(getDb(req)[corpus].assignments);
  }, 1000);
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/ClusterHosts", (req, res) => {
  const corpus = req.body.corpus.toLowerCase();
  return res.json(getDb(req)[corpus].hosts);
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/GetRepoStatus", (req, res) => {
  const data = req.body;
  if (data.repo_nwo === "github/github" || data.repo_id === "9919") {
    res.statusCode = 404;
    res.json({ code: "not_found", msg: "repo not found" });
  } else if (data.repo_nwo === "github/linguist" || data.repo_id === "1725199") {
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
        {
          corpus: "Red",
          epoch_id: 518,
          snapshot_entries: [],
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
        {
          corpus: "Red",
          epoch_id: 518,
          snapshot_entries: [],
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
    res.json(repoStatus);
  }
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/GetFilesetStatus", (req, res) => {
  let data = {
    repo_id: 2,
    fileset: "1/github/blackbird-refs/heads/main",
    serving_ingests: repoStatus.serving_ingests,
    indexer_ingests: repoStatus.indexer_ingests,
  };
  res.json(data);
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/FindAnything", (req, res) => {
  const data = req.body;
  if (data.q === "github/linguist") {
    res.json({
      repositories: [{ repo_id: 1725199, repo_nwo: "github/linguist" }],
      filesets: [],
      owners: [],
    });
  } else if (data.q === "1/github/blackbird-refs/heads/main") {
    res.json({
      repositories: [],
      filesets: [{ repo_id: 2, fileset: "1/github/blackbird-refs/heads/main" }],
      owners: [],
    });
  } else if (data.q === "tclem") {
    res.json({
      repositories: [],
      filesets: [],
      owners: [{ owner_id: 123, login: "tclem" }],
    });
  } else {
    res.json({
      repositories: [{ repo_id: 1725199, repo_nwo: "github/linguist", deleted_at: "2024-01-15T12:00:00Z" }],
      filesets: [{ repo_id: 2, fileset: "1/github/blackbird-refs/heads/main" }],
      owners: [{ owner_id: 123, login: "gorzell" }],
    });
  }
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/ProbeRepo", (req, res) => {
  const data = req.body;
  if (data.path === "non_utf8") {
    res.statusCode = 500;
    res.json({ code: "internal_server_error", msg: "Error: non_utf8 isn't indexed because due to one or more QoS filters: non-utf8, binary, 3 < file size < 358400" });
  } else if (data.path === "missing") {
    res.statusCode = 404;
    res.json({ code: "not_found", msg: "file not found" });
  } else {
    res.json({
      verified: 368,
      missing: ["example/missing/path"],
      extra: ["example/extra"],
      num_trailing_zeros: 0,
    });
  }
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusQueryState", (req, res) => {
  const corpus = req.body.corpus.toLowerCase();
  const db = getDb(req).corpora;

  let anotherServing = false;
  db.statuses.forEach((c) => {
    if (c.corpus_name.toLowerCase() !== corpus && c.serving) {
      anotherServing = true;
    }
  });

  if (!req.body.serving && !anotherServing && !req.body.force) {
    console.log("must have at least one serving corpus.");
    res.status(400).json({ msg: "must have at least one serving corpus." });
    return;
  }

  let c = db.statuses.find((c) => c.corpus_name.toLowerCase() === corpus);
  if (c !== undefined) {
    c.serving = req.body.serving;
  }
  res.json({});
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusShadowTraffic", (req, res) => {
  const corpus = req.body.corpus.toLowerCase();
  const db = getDb(req).corpora;
  db.statuses.forEach((c) => {
    if (c.corpus_name.toLowerCase() === corpus) {
      c.shadow_traffic_percent = req.body.percent;
    }
  });

  res.json({});
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusHealingRate", (req, res) => {
  const corpus = req.body.corpus.toLowerCase();
  const db = getDb(req).corpora;
  db.statuses.forEach((c) => {
    if (c.corpus_name.toLowerCase() === corpus) {
      c.healing_rate = req.body.healing_rate;
    }
  });

  res.json({});
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/BranchEpoch", (req, res) => {
  res.json({});
});

app.post("/twirp/blackbirdmw.admin.v1.AdminAPI/IndexRepoList", (req, res) => {
  res.json({});
});

app.post(
  [
    "/twirp/blackbirdmw.admin.v1.AdminAPI/IndexRepo",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/ResetRateLimitQuota",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/ChangeEpoch",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusIndexingState",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusInstantServingState",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusHealingState",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/PinCorpus",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/UnpinCorpus",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetCorpusCacheCluster",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/SetEpochDescription",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/BeginBackfillCorpus",
    "/twirp/blackbirdmw.admin.v1.AdminAPI/DeleteRepoEmbeddings",
  ],
  (req, res) => {
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
