## Memory usage estimates:

1 worker = processing 1 repo at a time

- spawnWorkers:RunIngest (concurrency = 1)
  - Ingest.process:ingestRepo
    - GetBlobs —
      - listBlobsInBatches (unbounded, up to 1GB or more?) — Max Mem: 1GiB
      - getBlobs (concurrency = 16, batch size = 25, maxBlobSize = 350 KiB) — Max Mem: ~136MiB
    - document.NewChange(msg, blob) - just a wrapper type, no allocations
    - publishChanges (concurrency = 10) —Max Mem: ~1GiB
      - change.ToDocument (NOTE: How much memory is enry using here?)
      - Build batches of 100MiB
      - Publish to blackbird-server

## Tuning Goal

Get 8 partitions (8 pods) performing to the best they can before dialing up partitions and pods. Eventually would like to try:
- Kafka partitions: 16
- Pods: 6 clusters of 2 pods = 12

## Baseline

- 8 partitions
- 12 pods (6 clusters with 2x pods ea.)
- 1 ingest worker
- getBlobs (concurrency = 16, batch size = 25)
- publishChanges (concurrency = 10, batch size = 100MiB)

Baseline ingest run observations
- ~25 mins to ingest 4442 repos (gaps in processing though due to un-equal work in partitions)
- 25 repos failed (spokesd: ListBlobsAtTips failed: twirp error unavailable: no available replicas found)
- 1 lagging partition (big repos on here?)
- CPU profile shows
  - go-enry modeline regex
  - spokesd.getBlobs
- Memory profile shows
  - spokesd.getBlobs (io.ReadAll)
  - spokesd.listBlobsAtTips (proto.UnMarshal, reflect.New)
  - indexDocuments (proto.Marshal)

## Notes and things to try

- Must be able to process multiple repos at once in a partition to avoid a large repo holding everything up
- Might want to use a weighted semaphore to take on work (weight = bytes of content? number of blobs?). We want to fully utilize a pods memory/cpu, but not take on work from kafka that we might have to drop (or will just content with other processing).
- Memory usage is high, can we bring this down? Seems to be mostly protocol buffers. Want to bring this down so that we can process multiple repos simultaneously.

## Tuning Log

Baseline:
- 1 ingest worker
- getBlobs (concurrency = 16, batch size = 25)
- publishChanges (concurrency = 10, batch size = 100MiB)

### 1. Try decreasing concurrency to lower memory usage.
- 1 ingest worker
- getBlobs (concurrency = 8, batch size = 25)
- publishChanges (concurrency = 8, batch size = 100MiB)

Observations:
- 26mins to ingest 4442 repos
- `blackbird-ingest-858dcdfdf6-ghjvs` used a ton of memory (processing repo_id=3 which is github/github).
  - It only processed 7 repos when I checked
  - Requests to blackbird are taking 2.5 minutes
- Indexing a few forks of github/github, why?
- Not keeping blackbird's queue full

Thoughts:
- Concurrency to blackbird doesn't matter right now b/c it's one queue anyway (this will change when we shard). Set it to something like 2
- Review repo selection, why forks for github/github?
-

### 2. Try no concurrency for true baseline
- 1 ingest worker
- getBlobs (concurrency = 1, batch size = 25)
- publishChanges (concurrency = 1, batch size = 100MiB)
- 200MiB queue in blackbird
- crossbeam backoff in blackbird

Observations:
- 2hrs to ingest 4442 repos
- 5GiB memory for blackbird-ingest-d6c7c758f-45dmw which processed repo_id:3. why?
  - At least 1/2 appears to be due to response from ListBlobsAtTips (2.06GB on the heap for that response alone).
- Not even close to saturating blackbird


### 3. Investigate memory usage for one repo
- single repo: 159554500
- Manual GC after publish documents
- 1 ingest worker
- getBlobs (concurrency = 1, batch size = 25)
- publishChanges (concurrency = 1, batch size = 100MiB)
- 200MiB queue in blackbird
- crossbeam backoff in blackbird

Observations:
- Was able to complete with stable 6.4GB mem usage
- Took over 2 hours!
- Why is so much memory required?
- Local testing of github/ghvfs-testing shows that LibBlobsAtTips returns 762M of data and over 3 million blob_oids

### 4. Investigate memory usage of GetBlobs
- single repo: 159554500
- exit early after reading all blobs (content)
- same settings as (3)

Observations:
- 8.92GiB of memory usage, does not get GC'd
- OOMKilled

### 5. Investigate memory usage of ListBlobsAtTips
- single repo: 159554500
- exit early after listing blob_oids
- same settings as (3)

Observations:
- 5.97GiB peak memory usage

### 6. Investigate memory usage of ListBlobsAtTips with manual GC
- single repo: 159554500
- manual GC
- exit early after listing blob_oids
- same settings as (3)

Observations:
- 5.81GiB Peak, drops to 2.15GiB after GC
- Didn't really help

### 7. Switch to github.com/gogo/protobuf
- single repo: 159554500
- manual GC
- exit early after listing blob_oids
- same settings as (3)

Observations:
- Still 5.8GB of memory usage :(

Reverted this change

### 8. Increase memory, limit inflight processing based on repo disk size
- 1 ingest worker
- up to 10GiB of inflightWork allowed
- getBlobs (concurrency = 16, batch size = 25)
- toDocument (concurrency = 32)
- publishChanges (concurrency = 4, batch size = 100MiB)
- 200MiB queue in blackbird
- crossbeam backoff in blackbird

Observations:
- 38min to ingest 4447 repos
- If multiple big repos end up on same partition, that partition is the long poll in the process

### 9. 2 ingest workers
- 2 ingest workers
- Set partition key to repo_id in blackbird-repo-generator
- up to 10GiB of inflightWork allowed
- getBlobs (concurrency = 16, batch size = 25)
- toDocument (concurrency = 32)
- publishChanges (concurrency = 4, batch size = 100MiB)
- 200MiB queue in blackbird
- crossbeam backoff in blackbird

Observations:
- to ingest 4447 repos
- even work distribution between partitions (same size at start)
- one partition doesn't move for most of the run (big repo)
- blackbird is a little business to start.. then it's starved
- pods are using more max memory (up to 8GB compared to previous run of 6GB max)

### 9. 2 ingest workers match getBlobs and toDocument concurrency
- 2 ingest workers
- Set partition key to repo_id in blackbird-repo-generator
- up to 15GiB of inflightWork allowed
- 10GiB max repo size on disk
- getBlobs (concurrency = 32, batch size = 25)
- toDocument (concurrency = 32)
- publishChanges (concurrency = 10, batch size = 100MiB)
- 200MiB queue in blackbird
- crossbeam backoff in blackbird

Observations:
- Haven't actually been using 2 workers :) wrong config for last two runs
- Re-deployed in the middle to see the change to 2 workers

### 9. 3 ingest workers match getBlobs and toDocument concurrency
- 3 ingest workers
- Set partition key to repo_id in blackbird-repo-generator
- up to 15GiB of inflightWork allowed
- 10GiB max repo size on disk
- getBlobs (concurrency = 32, batch size = 25)
- toDocument (concurrency = 32)
- publishChanges (concurrency = 10, batch size = 100MiB)
- 200MiB queue in blackbird
- crossbeam backoff in blackbird

Observations:
- 1 container OOMKilled

### 9. 3 ingest workers lower getBlobs and toDocument concurrency
- 3 ingest workers
- Set partition key to repo_id in blackbird-repo-generator
- up to 15GiB of inflightWork allowed
- 10GiB max repo size on disk
- getBlobs (concurrency = 16, batch size = 25)
- toDocument (concurrency = 16)
- publishChanges (concurrency = 10, batch size = 100MiB)
- 200MiB queue in blackbird
- crossbeam backoff in blackbird

Observations:
- 1 container OOMKilled
- 24mins to ingest 4447 repos

### 10. Bump blackbird's queue 10x
- 20GiB queue in blackbird

Observations:
- 1 container OOMKilled
- 28mins to ingest 4447 repos
- Longest requests to blackbird taking 14minutes

### 11. Blackbird: blocked requests go first
- prioritize existing blocked requests

Observations:
- 30min to ingest 4447 repos
- About the same as before
- OOMKill on one pod

### 12. Limit publish concurrency
- publishChanges (concurrency = 1, batch size = 100MiB)

Observations:
- 23min to ingest 4447 repos
- No OOMKilled
