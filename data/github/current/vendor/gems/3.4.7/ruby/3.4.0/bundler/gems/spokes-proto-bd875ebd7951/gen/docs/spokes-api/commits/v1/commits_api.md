[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/commits/v1/commits_api.proto



## Services

<a name="github.spokes.commits.v1.CommitsAPI"></a>

### CommitsAPI

CommitsAPI contains APIs for commit-related Git operations.

<a name="github.spokes.commits.v1.CommitsAPI-CheckCommitReachability"></a>

#### CheckCommitReachability

CheckCommitReachability checks whether the selected commits are reachable from a branch or tag.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.commits.v1.CommitsAPI/CheckCommitReachability`

<a name="github.spokes.commits.v1.CheckCommitReachabilityRequest"></a>

##### CheckCommitReachabilityRequest

CheckCommitReachability checks whether the selected commits are reachablle from a branch or tag.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) object_id_selector | [github.spokes.types.selectors.v1.ObjectIDSelector](../../types/selectors/v1/object_id_selector.md#github.spokes.types.selectors.v1.ObjectIDSelector) |  | object_id_selector is a selector for picking individual commits by id. |



<a name="github.spokes.commits.v1.CheckCommitReachabilityResponse"></a>

##### CheckCommitReachabilityResponse

CheckCommitReachabilityResponse contains a list of reachable commits.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| commits | [github.spokes.types.v1.ObjectID](../../types/v1/object_id.md#github.spokes.types.v1.ObjectID) | repeated | commits contains the list of commits that are reachable |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.commits.v1.CommitsAPI-ListCommits"></a>

#### ListCommits

ListCommits returns a list of commits based on a selector.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.commits.v1.CommitsAPI/ListCommits`

<a name="github.spokes.commits.v1.ListCommitsRequest"></a>

##### ListCommitsRequest

ListCommitsRequest returns a list of commits based on a selector.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) object_id_selector | [github.spokes.types.selectors.v1.ObjectIDSelector](../../types/selectors/v1/object_id_selector.md#github.spokes.types.selectors.v1.ObjectIDSelector) |  | object_id_selector is a selector for picking individual commits by id. |
| (oneof selector) push_selector | [github.spokes.types.selectors.v1.PushSelector](../../types/selectors/v1/push_selector.md#github.spokes.types.selectors.v1.PushSelector) |  | push_selector is a selector for picking commits based on (ref, before, after) tuples. |
| (oneof selector) universal_selector | [github.spokes.types.selectors.v1.UniversalSelector](../../types/selectors/v1/universal_selector.md#github.spokes.types.selectors.v1.UniversalSelector) |  | universal_selector selects all commits in the repository that are reachable from any reference, including our hidden bookkeeping references. |
| (oneof selector) revision_selector | [github.spokes.types.selectors.v1.RevisionSelector](../../types/selectors/v1/revision_selector.md#github.spokes.types.selectors.v1.RevisionSelector) |  | revision_selector is a selector for choosing the commits to list based on a Git revision (https://git-scm.com/docs/gitrevisions) |
| (oneof selector) fork_push_selector | [github.spokes.types.selectors.v1.ForkPushSelector](../../types/selectors/v1/fork_push_selector.md#github.spokes.types.selectors.v1.ForkPushSelector) |  | fork_push_selector is a push to select in a fork repository. |
| (oneof selector) historical_push_selector | [github.spokes.types.selectors.v1.HistoricalPushSelector](../../types/selectors/v1/historical_push_selector.md#github.spokes.types.selectors.v1.HistoricalPushSelector) |  | historical_push_selector is a selector for selecting picking commits from past pushes based on (ref, before, after) tuples. |
| (oneof selector) revision_and_path_selector | [github.spokes.types.selectors.v1.RevisionAndPathSelector](../../types/selectors/v1/revision_and_path_selector.md#github.spokes.types.selectors.v1.RevisionAndPathSelector) |  | revision_and_path_selector is a selector for picking commits based on Git revisions for a given path. <br>DEPRECATED: this selector option will be removed in future versions of this endpoint, use `RevisionSelector` with a `Pathspec` to specify a revision at a path. |
| (oneof selector) quarantine_commits_selector | [github.spokes.types.selectors.v1.QuarantineCommitsSelector](../../types/selectors/v1/quarantine_commits_selector.md#github.spokes.types.selectors.v1.QuarantineCommitsSelector) |  | quarantine_commits_selector selects commits in a push, when it's in quarantine. |
| (oneof selector) distinct_commits_selector | [github.spokes.types.selectors.v1.DistinctCommitsSelector](../../types/selectors/v1/distinct_commits_selector.md#github.spokes.types.selectors.v1.DistinctCommitsSelector) |  | distinct_commits_selector selects commits that are unique to the target branch. |
| filters | [RevListFilters](rev_list_filters.md#github.spokes.commits.v1.RevListFilters) |  | Filter the commits returned by this request. <br>Incompatible with distinct_commits_selector. |



<a name="github.spokes.commits.v1.ListCommitsResponse"></a>

##### ListCommitsResponse

ListCommitsResponse contains a list of commits.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| commits | [CommitItem](commit_item.md#github.spokes.commits.v1.CommitItem) | repeated | commits is the commits found based on the selector. |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.commits.v1.CommitsAPI-CountCommits"></a>

#### CountCommits

CountCommits returns a count of commits based on a selector.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.commits.v1.CommitsAPI/CountCommits`

<a name="github.spokes.commits.v1.CountCommitsRequest"></a>

##### CountCommitsRequest

CountCommitsRequest returns a count of commits based on a selector.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) object_id_selector | [github.spokes.types.selectors.v1.ObjectIDSelector](../../types/selectors/v1/object_id_selector.md#github.spokes.types.selectors.v1.ObjectIDSelector) |  | object_id_selector is a selector for picking individual commits by id. |
| (oneof selector) distinct_commits_selector | [github.spokes.types.selectors.v1.DistinctCommitsSelector](../../types/selectors/v1/distinct_commits_selector.md#github.spokes.types.selectors.v1.DistinctCommitsSelector) |  | distinct_commits_selector selects commits that are unique to the target branch. |
| (oneof selector) revision_selector | [github.spokes.types.selectors.v1.RevisionSelector](../../types/selectors/v1/revision_selector.md#github.spokes.types.selectors.v1.RevisionSelector) |  | revision_selector is a selector for choosing the commits to list based on a Git revision (https://git-scm.com/docs/gitrevisions) |
| filters | [RevListFilters](rev_list_filters.md#github.spokes.commits.v1.RevListFilters) |  | Filter the commits returned by this request. <br>Incompatible with distinct_commits_selector. |
| limit | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  |  |



<a name="github.spokes.commits.v1.CountCommitsResponse"></a>

##### CountCommitsResponse

CountCommitsResponse contains the count of commits based on the provided selector.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| count | [uint64](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  |  |



<a name="github.spokes.commits.v1.CommitsAPI-ListContributors"></a>

#### ListContributors

ListContributors returns a list of contributors that should be charged for Advanced Security.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.commits.v1.CommitsAPI/ListContributors`

<a name="github.spokes.commits.v1.ListContributorsRequest"></a>

##### ListContributorsRequest

ListContributorsRequest returns a list of contributors (authors and co-authors) associated with the selected commits. Used for billing.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |
| (oneof selector) push_selector | [github.spokes.types.selectors.v1.PushSelector](../../types/selectors/v1/push_selector.md#github.spokes.types.selectors.v1.PushSelector) |  | push_selector is a selector for picking commits based on (ref, before, after) tuples. |
| (oneof selector) historical_push_selector | [github.spokes.types.selectors.v1.HistoricalPushSelector](../../types/selectors/v1/historical_push_selector.md#github.spokes.types.selectors.v1.HistoricalPushSelector) |  | historical_push_selector is a selector for selecting picking commits from past pushes based on (ref, before, after) tuples. |



<a name="github.spokes.commits.v1.ListContributorsResponse"></a>

##### ListContributorsResponse

ListContributorsResponse contains a list of contributors (authors and co-authors) associated with the selected commits. Used for billing.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| contributors | [Contributor](#github.spokes.commits.v1.Contributor) | repeated | contributors contains the distinct contributors associated with the requested commits. |
| next_cursor | [github.spokes.types.v1.Cursor](../../types/v1/cursor.md#github.spokes.types.v1.Cursor) |  |  |



<a name="github.spokes.commits.v1.CommitsAPI-AheadBehind"></a>

#### AheadBehind

AheadBehind returns a list of ahead/behind values for a list of
commit tips relative to a common base commit.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.commits.v1.CommitsAPI/AheadBehind`

<a name="github.spokes.commits.v1.AheadBehindRequest"></a>

##### AheadBehindRequest

AheadBehindRequest returns a list of ahead/behind pairs for a list of
tip commits relative to a common base commit.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| (oneof selector) base_and_tips_selector | [BaseAndTipsSelector](#github.spokes.commits.v1.BaseAndTipsSelector) |  | base_and_tips_selector allows specifying a single base and multiple tips. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.commits.v1.AheadBehindResponse"></a>

##### AheadBehindResponse

AheadBehindResponse contains a list of ahead/behind pairs.
* Used for the branches page.
* Used for checking which pull requests were merged by a push to the
  default branch.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| ahead_behind_pairs | [AheadBehindPair](#github.spokes.commits.v1.AheadBehindPair) | repeated | ahead_behind_pairs lists the values that could be determined from the input tips. |



<a name="github.spokes.commits.v1.CommitsAPI-AheadBehindContains"></a>

#### AheadBehindContains

AheadBehindContains returns a list of tips which are contained in a base.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.commits.v1.CommitsAPI/AheadBehindContains`

<a name="github.spokes.commits.v1.AheadBehindContainsRequest"></a>

##### AheadBehindContainsRequest

AheadBehindContainsRequest returns a list of tips which are contained
in a given base (but not how far behind those tips are).


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| (oneof selector) base_and_tips_selector | [BaseAndTipsSelector](#github.spokes.commits.v1.BaseAndTipsSelector) |  | base_and_tips_selector allows specifying a single base and multiple tips. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.commits.v1.AheadBehindContainsResponse"></a>

##### AheadBehindContainsResponse

AheadBehindContainsResponse contains a list of tips which are
contained in the base.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| tips | [github.spokes.types.v1.Revision](../../types/v1/revision.md#github.spokes.types.v1.Revision) | repeated | tips is a list of tips which are contained in the base. |



<a name="github.spokes.commits.v1.CommitsAPI-BlameTree"></a>

#### BlameTree

BlameTree returns a list of oid/path pairs for the most-recent
commit to change that path.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.commits.v1.CommitsAPI/BlameTree`

<a name="github.spokes.commits.v1.BlameTreeRequest"></a>

##### BlameTreeRequest

BlameTreeRequest takes a commit, path, and recursive flag and returns
a list of oid/path pairs representing the most-recent commit oid to
touch the given path.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| (oneof selector) blame_tree_selector | [BlameTreeSelector](#github.spokes.commits.v1.BlameTreeSelector) |  | blame_tree_selector specifies a starting commit, path, and recursion. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.commits.v1.BlameTreeResponse"></a>

##### BlameTreeResponse

BlameTreeResponse consists of a list of OID/Path pairs.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| pairs | [CommitPathPair](#github.spokes.commits.v1.CommitPathPair) | repeated |  |



<a name="github.spokes.commits.v1.CommitsAPI-Describe"></a>

#### Describe

Describe returns a byte name of the commit

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.commits.v1.CommitsAPI/Describe`

<a name="github.spokes.commits.v1.DescribeRequest"></a>

##### DescribeRequest

Describe generates a human-readable name for a given commitish. 
An optional abbreviation length can be used to configure the OID suffix to the name.


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| (oneof selector) commitish_selector | [github.spokes.types.selectors.v1.CommitishSelector](../../types/selectors/v1/commitish_selector.md#github.spokes.types.selectors.v1.CommitishSelector) |  | commitish_selector selects a commit by its commitish. |
| abbrev_length | [uint32](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | length is the OID abbreviation length in the human-readable revision name. If zero or unset, defaults to the full OID length. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  |  |



<a name="github.spokes.commits.v1.DescribeResponse"></a>

##### DescribeResponse

DescribeResponse returns the name of the commit


| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| commit_name | [bytes](https://developers.google.com/protocol-buffers/docs/proto3#scalar) |  | Name of the commit |



