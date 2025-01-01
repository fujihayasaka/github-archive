package ts

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strconv"
	"strings"

	"github.com/github/turboscan/ts/transforms"

	"github.com/github/turboscan/ts/proto"

	"github.com/pkg/errors"
)

var (
	ErrRuleNotFound = errors.New("rule not found")
)

type RuleID uint64

// RuleHash contains the binary version of a sha256 checksum
// technically it is a []byte or [sha256.Size]byte, but
// using a string type has some nice properties, namely:
// it works natively with sql.Driver and it can be used as a key in hashes
type RuleHash string

func (rh *RuleHash) String() string {
	if rh == nil {
		return ""
	}
	return hex.EncodeToString([]byte(*rh))
}

// RuleKey allows you to look up a version of a Rule
type RuleKey struct {
	SarifIdentifier string
	Hash            RuleHash
}

// Rule describes a check performed by the tool.
//
// A Rule has a logical identity given by its SARIF identifier
// For example, CodeQL queries are use the @id metadata in the header comment.
// WARNING: make sure to extend the equality definition in InSync, when extending this.
type Rule struct {
	BaseModel
	ID               RuleID `verify:"ignore"`
	ToolID           ToolID `verify:"ignore"` // Identifies the SARIF 'driver' tool component
	SarifIdentifier  string
	Name             string
	ShortDescription string
	FullDescription  string
	HelpURI          string
	Help             string
	SeverityLevel    SeverityLevel
	SecuritySeverity *float64
	PrecisionLevel   PrecisionLevel
	QueryURI         string
	Hash             *RuleHash

	DefiningToolVersionID ToolVersionID `gorm:"-" verify:"ignore"` // The version of the tool component that defines the rule, if any. Only used when processing a delivery. 0 means missing

	// Associations
	Tags []RuleTag
	Tool *Tool `verify:"ignore"`
}

func (r *Rule) beforeVerify() *Rule {
	if r == nil {
		return nil
	}
	out := *r
	out.Tags = sorted(out.Tags)
	return &out
}

func (r *Rule) Key() (RuleKey, error) {
	if r.Hash == nil {
		err := r.UpdateHash()
		if err != nil {
			return RuleKey{}, err
		}
	}
	return RuleKey{
		Hash:            *r.Hash,
		SarifIdentifier: r.SarifIdentifier,
	}, nil
}

// RuleFilter defines the filtering conditions to apply to a Rule query.
type RuleFilter struct {
	SarifIdentifiers []string
	Tags             []string
	RepoID           RepositoryEID
	ToolIDs          []ToolID
	SearchQuery      string
}

// PrecisionLevel is an enumerative type describing the perceived accuracy of
// a rule. Possible values are: 'very-high', 'high', 'medium', 'low', 'unknown'
type PrecisionLevel uint8

const (
	PrecisionLevelUnknown  PrecisionLevel = 0
	PrecisionLevelLow      PrecisionLevel = 5
	PrecisionLevelMedium   PrecisionLevel = 10
	PrecisionLevelHigh     PrecisionLevel = 20
	PrecisionLevelVeryHigh PrecisionLevel = 30
)

func (pl PrecisionLevel) String() string {
	switch pl {
	case PrecisionLevelVeryHigh:
		return "very-high"
	case PrecisionLevelHigh:
		return "high"
	case PrecisionLevelMedium:
		return "medium"
	case PrecisionLevelLow:
		return "low"
	case PrecisionLevelUnknown:
		return "unknown"
	default:
		return "unknown"
	}
}

func (pl PrecisionLevel) IsValid() bool {
	switch pl {
	case PrecisionLevelUnknown, PrecisionLevelLow,
		PrecisionLevelMedium, PrecisionLevelHigh,
		PrecisionLevelVeryHigh:
		return true
	default:
		return false
	}
}

// SetPrecision sets the Precision and PrecisionLevel for the rule.
func (r *Rule) SetPrecision(p string) {
	switch p {
	case "very-high":
		r.PrecisionLevel = PrecisionLevelVeryHigh
	case "high":
		r.PrecisionLevel = PrecisionLevelHigh
	case "medium":
		r.PrecisionLevel = PrecisionLevelMedium
	case "low":
		r.PrecisionLevel = PrecisionLevelLow
	default:
		r.PrecisionLevel = PrecisionLevelUnknown
	}
}

// Match the SecuritySeverity to a SecuritySeverityLevel using the defined ranges
func getSecuritySeverityLevel(securitySeverity *float64) proto.SecuritySeverity {
	if securitySeverity == nil {
		return proto.SecuritySeverity_NO_SECURITY_SEVERITY
	}

	if *securitySeverity > 10.0 || *securitySeverity <= 0.0 {
		return proto.SecuritySeverity_NO_SECURITY_SEVERITY
	}

	if *securitySeverity >= 9.0 {
		return proto.SecuritySeverity_CRITICAL
	}

	if *securitySeverity >= 7.0 {
		return proto.SecuritySeverity_HIGH
	}

	if *securitySeverity >= 4.0 {
		return proto.SecuritySeverity_MEDIUM
	}

	return proto.SecuritySeverity_LOW
}

// SecuritySeverityLevel returns the securitySeverity mapped into
// a SecuritySeverityLevel enum value
func (r *Rule) SecuritySeverityLevel() proto.SecuritySeverity {
	return getSecuritySeverityLevel(r.SecuritySeverity)
}

// SeverityLevel is an enumerative type describing the severity of a a
// result. Typically defined at the rule level, and thus defined here.
// Possible values are: 'warning', 'error', 'note', 'none'
type SeverityLevel uint8

const (
	SeverityLevelNone    SeverityLevel = 0
	SeverityLevelNote    SeverityLevel = 10
	SeverityLevelWarning SeverityLevel = 20
	SeverityLevelError   SeverityLevel = 30
)

func (sl SeverityLevel) String() string {
	switch sl {
	case SeverityLevelWarning:
		return "Warning"
	case SeverityLevelError:
		return "Error"
	case SeverityLevelNote:
		return "Note"
	case SeverityLevelNone:
		return "None"
	default:
		panic("Invalid SeverityLevel value")
	}
}

// NewSeverityLevel returns a severity level value corresponding to
// the given string value.
func NewSeverityLevel(s string) (SeverityLevel, error) {
	switch strings.ToLower(s) {
	case "warning":
		return SeverityLevelWarning, nil
	case "error":
		return SeverityLevelError, nil
	case "note":
		return SeverityLevelNote, nil
	case "none":
		return SeverityLevelNone, nil
	default:
		// Severity level does not count as sensitive data
		return SeverityLevelNone, errors.Errorf("invalid severity level value: %s", s)
	}
}

// NewSecuritySeverityLevel returns the security severity object corresponding to
// the given string value.
func NewSecuritySeverityLevel(s string) (proto.SecuritySeverity, error) {
	switch strings.ToUpper(s) {
	case "NO_SECURITY_SEVERITY":
		return proto.SecuritySeverity_NO_SECURITY_SEVERITY, nil
	case "LOW":
		return proto.SecuritySeverity_LOW, nil
	case "MEDIUM":
		return proto.SecuritySeverity_MEDIUM, nil
	case "HIGH":
		return proto.SecuritySeverity_HIGH, nil
	case "CRITICAL":
		return proto.SecuritySeverity_CRITICAL, nil
	default:
		return proto.SecuritySeverity_NO_SECURITY_SEVERITY, errors.Errorf("invalid security severity level value: %s", s)
	}
}

func (sl SeverityLevel) IsValid() bool {
	switch sl {
	case SeverityLevelNone, SeverityLevelNote,
		SeverityLevelWarning, SeverityLevelError:
		return true
	default:
		return false
	}
}

// RuleTag provides tag annotations to a Rule
//
// Rule tags are extracted from the SARIF `properties` section of a
// rule, and might be empty.
type RuleTag struct {
	BaseModel
	ID     uint64
	RuleID RuleID
	Tag    string
}

func (rt RuleTag) Equal(other RuleTag) bool {
	return rt.Tag == other.Tag
}

func (rt RuleTag) Compare(other RuleTag) int {
	return strings.Compare(rt.Tag, other.Tag)
}

// RuleTagFilter defines the filtering conditions to apply to a RuleTag query.
type RuleTagFilter struct {
	RepoID  RepositoryEID
	ToolIDs []ToolID
}

// IsValid validates the Rule object:
// 1. SeverityLevel is set to a good value
func (r *Rule) IsValid() error {
	if !r.SeverityLevel.IsValid() {
		return errors.Errorf("invalid value '%d' for SeverityLevel", r.SeverityLevel)
	}
	return nil
}

// UpdateHash updates the Hash attribute based on all the data associated with this rule if it is not already set to
// a value.
func (r *Rule) UpdateHash() error {
	if r.Hash != nil {
		return nil
	}

	var err error

	sev := ""
	if r.SecuritySeverity != nil {
		sev = strconv.FormatFloat(*r.SecuritySeverity, 'f', -1, 64)
	}

	tags, err := r.GetTags()
	if err != nil {
		return err
	}

	// the default database collation does a case-insensitive sort
	// do the same to mirror the transition add_hash_to_ts_rules
	sort.Slice(tags, func(i, j int) bool {
		return strings.Compare(
			strings.ToLower(tags[i]),
			strings.ToLower(tags[j]),
		) < 0
	})

	var buf bytes.Buffer
	buf.Grow(sha256.Size * len(tags))

	for _, tag := range tags {
		h := sha256.Sum256([]byte(tag))
		_, err := buf.Write(h[:])
		if err != nil {
			return err
		}
	}

	hash := sha256.New()

	//  This hash function has a second implementation in SQL which is used in the transition add_hash_to_ts_rules.
	for _, val := range []string{
		// these are in database column order as per ts_rules.sql
		r.Name,
		r.ShortDescription,
		r.FullDescription,
		r.HelpURI,
		r.Help,
		strconv.Itoa(int(r.SeverityLevel)),
		sev,
		strconv.Itoa(int(r.PrecisionLevel)),
		r.QueryURI,
		// also make the tags part of the hash function
		buf.String(),
	} {
		d := sha256.Sum256([]byte(val))
		h := []byte(hex.EncodeToString(d[:]))

		_, err := hash.Write(h)
		if err != nil {
			return err
		}
	}
	data := RuleHash(hash.Sum(nil))
	r.Hash = &data
	return err
}

// BeforeSave is used by GORM before trying to create or update the DB
func (r *Rule) BeforeSave() error {
	err := r.UpdateHash()
	if err != nil {
		return err
	}

	return r.IsValid()
}

// AfterFind is used by GORM before returning an object from the DB
func (r *Rule) AfterFind() error {
	return r.IsValid()
}

var errTagsNotLoaded = errors.New("rule loaded without preloading tags")

// GetTags returns a slice of strings with the values of the Tags
// associated with the rule
func (r *Rule) GetTags() ([]string, error) {
	if r.Tags == nil && r.ID != 0 {
		return nil, errTagsNotLoaded
	}
	return transforms.Map(r.Tags, func(t RuleTag) string {
		return t.Tag
	}), nil
}

// SetTags sets the tags of the rule, ensuring that duplicates are removed
// This function is case-insensitive.
func (r *Rule) SetTags(tags []string) {
	normalized := make(map[string]bool)

	ruleTags := []RuleTag{}
	for _, tag := range tags {
		tagNormalized := strings.ToLower(tag)
		if _, exists := normalized[tagNormalized]; exists {
			continue
		}

		normalized[tagNormalized] = true
		ruleTags = append(ruleTags, RuleTag{Tag: tag})
	}

	r.Tags = ruleTags
}

// HasTag returns true if the rule has the given tag, false otherwise
func (r *Rule) HasTag(tag string) bool {
	for _, curr := range r.Tags {
		if curr.Tag == tag {
			return true
		}
	}
	return false
}

// AnalysisRule association
type AnalysisRule struct {
	ID                    uint64
	RepositoryID          RepositoryEID
	AnalysisID            AnalysisID
	RuleID                RuleID
	DefiningToolVersionID ToolVersionID // The id of the tool that defined the rule. 0 if unknown / the rule had no associated tool.

	// associations
	Rule *Rule
}
