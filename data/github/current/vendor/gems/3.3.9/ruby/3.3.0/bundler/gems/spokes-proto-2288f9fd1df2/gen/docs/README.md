# Spokes Access API

## Services


### [Backups API](spokes-api/backups/v1/backups_api.md#github.spokes.backups.v1.BackupsAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[PerformBackup](spokes-api/backups/v1/backups_api.md#github.spokes.backups.v1.BackupsAPI-PerformBackup) | [PerformBackupRequest](spokes-api/backups/v1/backups_api.md#github.spokes.backups.v1.PerformBackupRequest) | [PerformBackupResponse](spokes-api/backups/v1/backups_api.md#github.spokes.backups.v1.PerformBackupResponse)

### [Blobs API](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.BlobsAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[GetBlobContents](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.BlobsAPI-GetBlobContents) | [GetBlobContentsRequest](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.GetBlobContentsRequest) | [GetBlobContentsResponse](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.GetBlobContentsResponse)
[ListChangedBlobs](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.BlobsAPI-ListChangedBlobs) | [ListChangedBlobsRequest](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.ListChangedBlobsRequest) | [ListChangedBlobsResponse](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.ListChangedBlobsResponse)
[ListReachableBlobs](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.BlobsAPI-ListReachableBlobs) | [ListReachableBlobsRequest](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.ListReachableBlobsRequest) | [ListReachableBlobsResponse](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.ListReachableBlobsResponse)
[ListBlobOrigin](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.BlobsAPI-ListBlobOrigin) | [ListBlobOriginRequest](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.ListBlobOriginRequest) | [ListBlobOriginResponse](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.ListBlobOriginResponse)
[ListPushedBlobs](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.BlobsAPI-ListPushedBlobs) | [ListPushedBlobsRequest](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.ListPushedBlobsRequest) | [ListPushedBlobsResponse](spokes-api/blobs/v1/blobs_api.md#github.spokes.blobs.v1.ListPushedBlobsResponse)

### [Commits API](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CommitsAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[CheckCommitReachability](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CommitsAPI-CheckCommitReachability) | [CheckCommitReachabilityRequest](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CheckCommitReachabilityRequest) | [CheckCommitReachabilityResponse](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CheckCommitReachabilityResponse)
[ListCommits](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CommitsAPI-ListCommits) | [ListCommitsRequest](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.ListCommitsRequest) | [ListCommitsResponse](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.ListCommitsResponse)
[ListContributors](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CommitsAPI-ListContributors) | [ListContributorsRequest](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.ListContributorsRequest) | [ListContributorsResponse](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.ListContributorsResponse)
[AheadBehind](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CommitsAPI-AheadBehind) | [AheadBehindRequest](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.AheadBehindRequest) | [AheadBehindResponse](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.AheadBehindResponse)
[AheadBehindContains](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CommitsAPI-AheadBehindContains) | [AheadBehindContainsRequest](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.AheadBehindContainsRequest) | [AheadBehindContainsResponse](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.AheadBehindContainsResponse)
[BlameTree](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.CommitsAPI-BlameTree) | [BlameTreeRequest](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.BlameTreeRequest) | [BlameTreeResponse](spokes-api/commits/v1/commits_api.md#github.spokes.commits.v1.BlameTreeResponse)

### [Diffs API](spokes-api/diffs/v1/diffs_api.md#github.spokes.diffs.v1.DiffsAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[ReadDiffSummary](spokes-api/diffs/v1/diffs_api.md#github.spokes.diffs.v1.DiffsAPI-ReadDiffSummary) | [ReadDiffSummaryRequest](spokes-api/diffs/v1/diffs_api.md#github.spokes.diffs.v1.ReadDiffSummaryRequest) | [ReadDiffSummaryResponse](spokes-api/diffs/v1/diffs_api.md#github.spokes.diffs.v1.ReadDiffSummaryResponse)

### [Diffs API](spokes-api/diffs/v2/diffs_api.md#github.spokes.diffs.v2.DiffsAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[ReadDiffSummary](spokes-api/diffs/v2/diffs_api.md#github.spokes.diffs.v2.DiffsAPI-ReadDiffSummary) | [ReadDiffSummaryRequest](spokes-api/diffs/v2/diffs_api.md#github.spokes.diffs.v2.ReadDiffSummaryRequest) | [ReadDiffSummaryResponse](spokes-api/diffs/v2/diffs_api.md#github.spokes.diffs.v2.ReadDiffSummaryResponse)

### [Experimental API](spokes-api/experimental/experimental_api.md#github.spokes.experimental.v1.ExperimentalAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[ResolveObjects](spokes-api/experimental/experimental_api.md#github.spokes.experimental.v1.ExperimentalAPI-ResolveObjects) | [ResolveObjectsRequest](spokes-api/experimental/experimental_api.md#github.spokes.experimental.v1.ResolveObjectsRequest) | [ResolveObjectsResponse](spokes-api/experimental/experimental_api.md#github.spokes.experimental.v1.ResolveObjectsResponse)

### [Gitauth API](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.GitauthAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[ListRoutes](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.GitauthAPI-ListRoutes) | [ListRoutesRequest](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.ListRoutesRequest) | [ListRoutesResponse](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.ListRoutesResponse)
[SetUpPushState](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.GitauthAPI-SetUpPushState) | [SetUpPushStateRequest](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.SetUpPushStateRequest) | [SetUpPushStateResponse](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.SetUpPushStateResponse)
[CommitQuarantine](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.GitauthAPI-CommitQuarantine) | [CommitQuarantineRequest](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.CommitQuarantineRequest) | [CommitQuarantineResponse](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.CommitQuarantineResponse)
[RemoveQuarantine](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.GitauthAPI-RemoveQuarantine) | [RemoveQuarantineRequest](spokes-api/gitauth/v1/gitauth_api.md#github.spokes.gitauth.v1.RemoveQuarantineRequest) | [Empty](https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#google.protobuf.Empty)

### [Hooks API](spokes-api/hooks/v1/hooks_api.md#github.spokes.hooks.v1.HooksAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[RunPreReceiveHooks](spokes-api/hooks/v1/hooks_api.md#github.spokes.hooks.v1.HooksAPI-RunPreReceiveHooks) | [RunPreReceiveHooksRequest](spokes-api/hooks/v1/hooks_api.md#github.spokes.hooks.v1.RunPreReceiveHooksRequest) | [RunPreReceiveHooksResponse](spokes-api/hooks/v1/hooks_api.md#github.spokes.hooks.v1.RunPreReceiveHooksResponse)

### [LegacyGitrpc API](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[LegacyGitrpcReader](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-LegacyGitrpcReader) | [LegacyGitrpcReaderRequest](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcReaderRequest) | [LegacyGitrpcReaderResponse](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcReaderResponse)
[LegacyGitrpcWriter](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-LegacyGitrpcWriter) | [LegacyGitrpcWriterRequest](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcWriterRequest) | [LegacyGitrpcWriterResponse](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcWriterResponse)
[Bertrpc](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-Bertrpc) | [BertrpcRequest](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.BertrpcRequest) | [BertrpcResponse](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.BertrpcResponse)
[GetCacheKey](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-GetCacheKey) | [GetCacheKeyRequest](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.GetCacheKeyRequest) | [GetCacheKeyResponse](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.GetCacheKeyResponse)
[GetCacheKeys](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.LegacyGitrpcAPI-GetCacheKeys) | [GetCacheKeysRequest](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.GetCacheKeysRequest) | [GetCacheKeysResponse](spokes-api/legacygitrpc/v1/legacygitrpc_api.md#github.spokes.legacygitrpc.v1.GetCacheKeysResponse)

### [Merges API](spokes-api/merges/v1/merges_api.md#github.spokes.merges.v1.MergesAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[FindMergeBases](spokes-api/merges/v1/merges_api.md#github.spokes.merges.v1.MergesAPI-FindMergeBases) | [FindMergeBasesRequest](spokes-api/merges/v1/merges_api.md#github.spokes.merges.v1.FindMergeBasesRequest) | [FindMergeBasesResponse](spokes-api/merges/v1/merges_api.md#github.spokes.merges.v1.FindMergeBasesResponse)

### [Objects API](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ObjectsAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[ResolveObject](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ObjectsAPI-ResolveObject) | [ResolveObjectRequest](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ResolveObjectRequest) | [ResolveObjectResponse](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ResolveObjectResponse)
[ResolveObjects](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ObjectsAPI-ResolveObjects) | [ResolveObjectsRequest](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ResolveObjectsRequest) | [ResolveObjectsResponse](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ResolveObjectsResponse)
[ExpandOids](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ObjectsAPI-ExpandOids) | [ExpandOidsRequest](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ExpandOidsRequest) | [ExpandOidsResponse](spokes-api/objects/v1/objects_api.md#github.spokes.objects.v1.ExpandOidsResponse)

### [References API](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ReferencesAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[ResolveReferences](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ReferencesAPI-ResolveReferences) | [ResolveReferencesRequest](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ResolveReferencesRequest) | [ResolveReferencesResponse](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ResolveReferencesResponse)
[ListReferences](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ReferencesAPI-ListReferences) | [ListReferencesRequest](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ListReferencesRequest) | [ListReferencesResponse](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ListReferencesResponse)
[GetDefaultBranch](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ReferencesAPI-GetDefaultBranch) | [GetDefaultBranchRequest](spokes-api/references/v1/references_api.md#github.spokes.references.v1.GetDefaultBranchRequest) | [GetDefaultBranchResponse](spokes-api/references/v1/references_api.md#github.spokes.references.v1.GetDefaultBranchResponse)
[ListReferencesWithDetails](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ReferencesAPI-ListReferencesWithDetails) | [ListReferencesWithDetailsRequest](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ListReferencesWithDetailsRequest) | [ListReferencesWithDetailsResponse](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ListReferencesWithDetailsResponse)
[Update](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ReferencesAPI-Update) | [UpdateRequest](spokes-api/references/v1/references_api.md#github.spokes.references.v1.UpdateRequest) | [UpdateResponse](spokes-api/references/v1/references_api.md#github.spokes.references.v1.UpdateResponse)
[UpdateDefaultBranch](spokes-api/references/v1/references_api.md#github.spokes.references.v1.ReferencesAPI-UpdateDefaultBranch) | [UpdateDefaultBranchRequest](spokes-api/references/v1/references_api.md#github.spokes.references.v1.UpdateDefaultBranchRequest) | [UpdateDefaultBranchResponse](spokes-api/references/v1/references_api.md#github.spokes.references.v1.UpdateDefaultBranchResponse)

### [Repositories API](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.RepositoriesAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[ListAvailableReplicas](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.RepositoriesAPI-ListAvailableReplicas) | [ListAvailableReplicasRequest](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.ListAvailableReplicasRequest) | [ListAvailableReplicasResponse](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.ListAvailableReplicasResponse)
[UpdateInfoNWO](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.RepositoriesAPI-UpdateInfoNWO) | [UpdateInfoNWORequest](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.UpdateInfoNWORequest) | [UpdateInfoNWOResponse](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.UpdateInfoNWOResponse)
[RecomputeChecksums](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.RepositoriesAPI-RecomputeChecksums) | [RecomputeChecksumsRequest](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.RecomputeChecksumsRequest) | [RecomputeChecksumsResponse](spokes-api/repositories/v1/repositories_api.md#github.spokes.repositories.v1.RecomputeChecksumsResponse)

### [Trees API](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.TreesAPI)

Method | Request Type | Response Type
------ | ------------ | -------------
[ListTrees](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.TreesAPI-ListTrees) | [ListTreesRequest](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.ListTreesRequest) | [ListTreesResponse](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.ListTreesResponse)
[CompareTrees](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.TreesAPI-CompareTrees) | [CompareTreesRequest](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.CompareTreesRequest) | [CompareTreesResponse](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.CompareTreesResponse)
[ReadTreeEntryOid](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.TreesAPI-ReadTreeEntryOid) | [ReadTreeEntryOidRequest](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.ReadTreeEntryOidRequest) | [ReadTreeEntryOidResponse](spokes-api/trees/v1/trees_api.md#github.spokes.trees.v1.ReadTreeEntryOidResponse)


### [StreamingAPI](spokes-api/streaming/v1/streaming_api.md)

Method | Request Type | Response Type
------ | ------------ | -------------
Get Blob (respository) | `GET /streaming/v1/repositories/{repository id}/blobs/{oid}` | blob in response body
Get Blob (gist) | `GET /streaming/v1/gist/{gist id}/blobs/{oid}` | blob in response body
Batch Get Blobs | [BatchBlobsRequest](spokes-api/streaming/v1/streaming_api.md#github.spokes.batch.v1.BatchBlobsRequest) | tar archive with one entry per blob

## Types


## Selectors

