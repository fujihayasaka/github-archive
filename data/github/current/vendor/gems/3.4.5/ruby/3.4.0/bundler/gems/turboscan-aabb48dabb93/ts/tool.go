package ts

import (
	"crypto/sha1" // nolint:gosec // G505 we need this to create a guid
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/google/uuid"
	"go.uber.org/zap/zapcore"
)

type ToolID uint64
type ToolVersionID uint64

const ToolVersionUnspecified = ToolVersionID(0)
const CodeQLCanonicalName = ToolName("CodeQL")

// A Tool represents a tool used to run an Analysis.
type Tool struct {
	BaseModel
	ID ToolID `verify:"ignore"`

	CanonicalName  ToolName
	GUID           string
	IsInternalGUID bool
}

func (t *Tool) IsCodeQL() bool {
	return IsCodeQL(t.CanonicalName)
}

func (t *Tool) beforeVerify() *Tool {
	if t == nil {
		return t
	}
	out := *t
	if name, ok := CanonicalToolRenames[out.CanonicalName]; ok {
		out.CanonicalName = name
	}
	// do not attempt to compare the guid if it was internally generated and not provided in the original SARIF
	if out.IsInternalGUID {
		out.GUID = ""
	}
	return &out
}

func ToolFromCanonicalName(canonicalName ToolName) *Tool {
	// generate a stable guid based on the canonical name
	hash := sha1.Sum([]byte(canonicalName)) // nolint:gosec // G401 this does not have to be cryptographically secure
	guid := uuid.Must(uuid.FromBytes(hash[:16]))

	return &Tool{
		GUID:           guid.String(),
		CanonicalName:  canonicalName,
		IsInternalGUID: true,
	}
}

// A ToolVersion represents a specific version of a tool.
// When adding a new field consider extending mysql/tool.go:getToolVersion
type ToolVersion struct {
	BaseModel
	ID ToolVersionID `verify:"ignore"`

	ToolID          ToolID `verify:"ignore"`
	Name            ToolName
	FullName        string
	Version         string
	SemanticVersion string

	IsCodeQLModelPack bool `gorm:"column:is_codeql_model_pack" verify:"ignore"`

	// Association
	Tool *Tool `verify:"ignore"`
}

func (tv *ToolVersion) Compare(other *ToolVersion) int {
	if tv.Name == other.Name {
		return strings.Compare(tv.Version, other.Version)
	}
	return strings.Compare(string(tv.Name), string(other.Name))
}

func (tv *ToolVersion) beforeVerify() *ToolVersion {
	if tv == nil {
		return tv
	}
	out := *tv
	if name, ok := CanonicalToolRenames[out.Name]; ok {
		out.Name = name
	}
	// The canonical name for tools is case-insensitive, so
	// the name might have changed after the initial loading.
	// Therefore we lower-case the values before comparing.
	// See https://github.com/github/code-scanning/issues/7568
	out.Name = out.Name.ToLower()
	return &out
}

// CanonicalToolRenames tracks the preferred name for a renamed tool
var CanonicalToolRenames = map[ToolName]ToolName{
	// CodeQL
	"CodeQL command-line toolchain": "CodeQL",
	// Golang
	"Golang security checks by gosec": "gosec",
	// Bandit
	"Security audit for python by bandit": "bandit",
}

// ToolRenames is a bi-directional mapping between tool renames
var ToolRenames = (func(m map[ToolName]ToolName) map[ToolName]ToolName {
	res := map[ToolName]ToolName{}
	for k, v := range m {
		res[k] = v
		res[v] = k
	}
	return res
})(CanonicalToolRenames)

func IsCodeQL(name ToolName) bool {
	if canonicalName, ok := CanonicalToolRenames[name]; ok {
		name = canonicalName
	}
	return name.Equals(CodeQLCanonicalName)
}

// GetVersion returns the version of the tool, by preferring the
// Semantic Version over the Version field when possible
func (tv ToolVersion) GetVersion() string {
	if tv.SemanticVersion != "" {
		return tv.SemanticVersion
	}
	return tv.Version
}

// ToolsFilter is used to select a list of Tools from a ToolService
// When searching, CanonicalNames will take precedence over the GUIDs.
type ToolsFilter struct {
	CanonicalNames []ToolName
	GUIDs          []string
}

type ToolName string255

func ToToolName(name string) ToolName {
	return ToolName(toString255(name))
}

func (n ToolName) Equals(other ToolName) bool {
	return strings.EqualFold(string(n), string(other))
}

func (n ToolName) String() string {
	return string(n)
}

func (n ToolName) ToLower() ToolName {
	return ToolName(strings.ToLower(string(n)))
}

func (n ToolName) AsKVP() zapcore.Field {
	return kvp.String("gh.turboscan.tool", string(n))
}
