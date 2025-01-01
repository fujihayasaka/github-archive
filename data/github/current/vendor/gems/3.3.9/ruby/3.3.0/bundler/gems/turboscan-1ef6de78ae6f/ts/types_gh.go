package ts

import (
	"encoding/binary"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

// These are all types that come from github.com/github/github.

// OwnerEID uint64 in the gh/gh database
type OwnerEID uint64

// AsKVP returns the repository id as a KVP field to use with the telemetry library
func (id OwnerEID) AsKVP() zapcore.Field {
	return kvp.Int("gh.owner.id", int(id))
}

// RepositoryEID represents the Repository ID in the gh/gh database
type RepositoryEID uint64

// AsKVP returns the repository id as a KVP field to use with the telemetry library
func (id RepositoryEID) AsKVP() zapcore.Field {
	return kvp.Int("gh.repo.id", int(id))
}

// ToBytes converts the repository id to a slice of bytes (e.g. for hashing)
func (id RepositoryEID) ToBytes() []byte {
	a := make([]byte, 8)
	binary.BigEndian.PutUint64(a, uint64(id))
	return a
}

// PullRequestEID represents the Pull Request ID in the gh/gh database
type PullRequestEID uint64

// AsKVP returns the repository id as a KVP field to use with the telemetry library
func (id PullRequestEID) AsKVP() zapcore.Field {
	return kvp.Int("gh.pull_request.id", int(id))
}

// UserEID represents the User ID in the gh/gh database
type UserEID uint32

// WorkflowRunEID represents the WorkflowRun ID in the gh/gh database
type WorkflowRunEID uint64

// AsKVP returns the repository id as a KVP field to use with the telemetry library
func (id WorkflowRunEID) AsKVP() zapcore.Field {
	return kvp.Uint64("gh.actions.workflow_run.id", uint64(id))
}

// WorkflowRunAttempt represents the workflow run attempt, as each workflow run can be "retried".
type WorkflowRunAttempt int64

// Ref represents a git ref
type Ref []byte

func (r Ref) String() string {
	return string(r)
}

func (r Ref) AsKVP() zapcore.Field {
	return kvp.ByteString("gh.git.ref", r)
}

const RefMaxSize = 1024

// Sha represents a git sha
type Sha string40

func ToSha(s string) Sha {
	return Sha(toString40(s))
}

func (s Sha) Short() string {
	return string(s[:7])
}

func (s Sha) AsKVP() zapcore.Field {
	return kvp.String("gh.commit.sha", string(s))
}

func (s Sha) String() string {
	return string(s)
}

const EmptySha = Sha("")

// ProximaTenant wraps the Tenant ID and Slug
type ProximaTenant struct {
	Slug string
	ID   int64
}

type RepositoryNWO string

func ToRepositoryNWO(nwo string) RepositoryNWO {
	return RepositoryNWO(toString140(nwo))
}

func (nwo RepositoryNWO) HasOwner(owner string) bool {
	idx := strings.Index(string(nwo), "/")
	if idx == -1 {
		return false
	}
	return string(nwo[:idx]) == owner
}

func (nwo RepositoryNWO) String() string {
	return string(nwo)
}

type CheckoutURI string1024

func ToCheckoutURI(uri string) CheckoutURI {
	return CheckoutURI(toString1024(uri))
}

func (uri CheckoutURI) String() string {
	return string(uri)
}

const EmptyCheckoutURI = CheckoutURI("")

type AnalysisKey string255

func ToAnalysisKey(key string) AnalysisKey {
	return AnalysisKey(toString255(key))
}

func (key AnalysisKey) String() string {
	return string(key)
}

type SarifID string255

// NewSarifID casts the input id into a SarifID, returning false if the string is too long.
// Note: It is meaningless to truncate a SarifID as it is meant to be a unique identifier.
func NewSarifID(id string) (SarifID, bool) {
	out, ok := newString255(id)
	return SarifID(out), ok
}

func (id SarifID) String() string {
	return string(id)
}

type Category string1000

func ToCategory(category string) Category {
	return Category(toString1000(category))
}

func (category Category) String() string {
	return string(category)
}

func (category Category) AsKVP() zapcore.Field {
	return kvp.String("gh.turboscan.category", string(category))
}

// RequestID encodes a github request id
type RequestID string255

func ToRequestID(id string) RequestID {
	return RequestID(toString255(id))
}

func (id RequestID) String() string {
	return string(id)
}

// WorkflowPath is a path to a workflow file
type WorkflowPath []byte

func ToWorkflowPath(path []byte) WorkflowPath {
	const maxLen = 1024
	if len(path) > maxLen {
		return path[:1024]
	}
	return path
}

func (p WorkflowPath) String() string {
	return string(p)
}

func (p WorkflowPath) Bytes() []byte {
	return []byte(p)
}

func EmptyWorkflowPath() WorkflowPath {
	return WorkflowPath{}
}

type ActorGRIDLogin struct {
	GRID  ActorGRID
	Login string
}

// SecurityCampaignEID represents the Security Campaign ID in the gh/gh database
type SecurityCampaignEID uint64
