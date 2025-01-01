package ts

import (
	"fmt"
	"strings"

	"github.com/SamuelTissot/sqltime"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
)

// Index represents the type of ElasticSearch index we intend to use.
type Index int

const (
	// This was used to distinguish between the initial index used for free-text search (i.e. `Index_FreeText`)
	// and the one that replaced it eventually.
	Index_OrgLevel = 1
)

var (
	ErrIndexNotFound      = errors.New("index not found")
	ErrStrictMapping      = errors.New("cannot modify strict index mapping")
	ErrInvalidQuerySyntax = errors.New("invalid ES query syntax")
)

// SearchDocument wraps the alert data to be indexed in the search cluster.
type SearchDocument struct {
	// Logical alert fields
	AlertID uint64 `json:"alert_id,omitempty"`
	Number  uint32 `json:"number,omitempty"`
	Weight  uint16 `json:"weight,omitempty"`

	SarifIdentifier  string   `json:"sarif_identifier,omitempty"`
	RuleName         string   `json:"rule_name,omitempty"`
	ShortDescription string   `json:"short_description,omitempty"`
	FullDescription  string   `json:"full_description,omitempty"`
	Help             string   `json:"help,omitempty"`
	Tags             []string `json:"tags,omitempty"`
	Severity         string   `json:"severity,omitempty"` // unified severity taking both Rule and Security severity into account

	Tool     string `json:"tool,omitempty"`
	ToolGUID string `json:"tool_guid,omitempty"`

	Resolution     string        `json:"resolution,omitempty"`
	Resolved       *bool         `json:"resolved,omitempty"`
	ResolverID     *UserEID      `json:"resolver_id,string,omitempty"`
	FixedOnDefault *bool         `json:"fixed_on_default,omitempty"`
	CreatedAt      *sqltime.Time `json:"created_at,omitempty"`
	// UpdatedAt value currently doesn't match updated_at field from the database
	// it currently matches the last_state_change_at field
	UpdatedAt  *sqltime.Time `json:"updated_at,omitempty"`
	FixedAt    *sqltime.Time `json:"fixed_at,omitempty"`
	ResolvedAt *sqltime.Time `json:"resolved_at,omitempty"`
	// InsightsUpdatedAt is an adjusted version of UpdatedAt to update data in SecOv accordingly when an autofix is generated or accepted.
	InsightsUpdatedAt *sqltime.Time `json:"insights_updated_at,omitempty"`

	// Physical alert fields
	CanonicalID    string   `json:"canonical_id,omitempty"`
	FilePath       string   `json:"file_path,omitempty"`
	Message        string   `json:"message,omitempty"`
	Classification []string `json:"classification,omitempty"`

	// Repository metadata fields
	RepositoryID        string `json:"repository_id,omitempty"`
	OwnerID             string `json:"owner_id,omitempty"`
	CodeScanningEnabled *bool  `json:"code_scanning_enabled,omitempty"`
	Visibility          string `json:"visibility,omitempty"`

	HasLinks bool `json:"has_links,omitempty"`

	// Autofix metadata fields
	AutofixEligible       bool          `json:"autofix_eligible,omitempty"`
	AutofixState          string        `json:"autofix_state,omitempty"`
	AutofixStateUpdatedAt *sqltime.Time `json:"autofix_state_updated_at,omitempty"`
	AutofixAccepted       bool          `json:"autofix_accepted,omitempty"`

	// Security campaigns
	SecurityCampaignIDs []string `json:"security_campaign_id,omitempty"`
}

type SearchFilter struct {
	QueryString          string
	RuleSarifIDs         []string
	RuleTags             []string
	ExcludedRuleTags     []string
	ExcludedRuleSarifIDs []string
}

// SearchByOrgsFilter contains fields for filtering results in single/multi-org searches
type SearchByOrgsFilter struct {
	OwnerIDs                                      []OwnerEID
	RepositoryIDs                                 []RepositoryEID
	ExcludedRepositoryIDs                         []RepositoryEID
	IncludeRepositoriesWithoutCodeScanningEnabled bool
	State                                         proto.AlertStateFilter
	ToolGUID                                      string
	Tool                                          string // TODO named to match ES index, but should we rename both to ToolCanonicalName?
	ToolGUIDs                                     []string
	Tools                                         []string
	ExcludedTools                                 []string // TODO named to match ES index, but should we rename both to ToolCanonicalName?
	Severity                                      proto.Severity
	Severities                                    []proto.Severity
	ExcludedSeverities                            []proto.Severity
	SarifIdentifier                               string
	SarifIdentifiers                              []string
	ExcludedSarifIdentifiers                      []string
	Tags                                          []string
	ExcludedTags                                  []string
	QueryString                                   string
	Resolution                                    *AlertResolution
	Resolutions                                   []*AlertResolution
	ExcludedResolutions                           []*AlertResolution
	RepositoryVisibilities                        []string
	LogicalAlertIDs                               []LogicalAlertID
	RepoNumbers                                   []RepoNumber
	Classification                                proto.AlertClassificationFilter
	AlertLinks                                    proto.AlertLinksFilter
	Autofixes                                     []proto.AutofixFilter
	ExcludedAutofixes                             []proto.AutofixFilter
	SecurityCampaignIDs                           []SecurityCampaignEID
	ExcludedSecurityCampaignIDs                   []SecurityCampaignEID
	CampaignPresence                              proto.CampaignPresenceFilter
}

type RepoNumber struct {
	RepositoryID RepositoryEID
	Number       uint32
}

type SearchResultsSort struct {
	Fields    []string
	Ascending bool
}

var AlertIDSort = SearchResultsSort{
	Fields:    []string{"alert_id"},
	Ascending: false,
}

var InsightsUpdatedAtSort = SearchResultsSort{
	Fields:    []string{"insights_updated_at", "alert_id"},
	Ascending: true,
}

var DefaultSearchResultsSort = AlertIDSort

func SearchSortFromProto(sortOrder proto.AlertSortOrder) SearchResultsSort {
	switch sortOrder {
	case proto.AlertSortOrder_WEIGHT:
		return SearchResultsSort{
			Fields:    []string{"weight", "updated_at", "alert_id"},
			Ascending: false,
		}
	case proto.AlertSortOrder_CREATED_ASCENDING:
		return SearchResultsSort{
			Fields:    []string{"created_at", "alert_id"},
			Ascending: true,
		}
	case proto.AlertSortOrder_CREATED_DESCENDING:
		return SearchResultsSort{
			Fields:    []string{"created_at", "alert_id"},
			Ascending: false,
		}
	case proto.AlertSortOrder_UPDATED_ASCENDING:
		return SearchResultsSort{
			Fields:    []string{"updated_at", "alert_id"},
			Ascending: true,
		}
	case proto.AlertSortOrder_UPDATED_DESCENDING:
		return SearchResultsSort{
			Fields:    []string{"updated_at", "alert_id"},
			Ascending: false,
		}
	}
	return DefaultSearchResultsSort
}

// SearchDocumentsFromAlerts creates documents form the logical alerts.
// It handles alerts from multiple repositories at the same time.
func SearchDocumentsFromAlerts(repository *Repository, alerts []*LogicalAlert) ([]*SearchDocument, error) {
	docs := make([]*SearchDocument, 0, len(alerts))

	for _, a := range alerts {
		a, err := setLastStateChangeAt(a)
		if err != nil {
			return nil, err
		}
		resolved := a.Resolution != AlertResolutionNone

		d := &SearchDocument{
			AlertID:        uint64(a.ID),
			Number:         a.Number,
			Weight:         a.Weight,
			Resolution:     a.Resolution.String(),
			Resolved:       &resolved,
			CreatedAt:      &a.CreatedAt,
			UpdatedAt:      a.LastStateChangeAt,
			FixedAt:        a.GetFixedAt(),
			ResolvedAt:     a.ResolvedAt,
			ResolverID:     a.ResolverID,
			RepositoryID:   fmt.Sprint(a.RepositoryID),
			Message:        a.Message,
			FilePath:       a.FilePath,
			Classification: a.FileClassification,
		}

		var severity string

		if a.Rule != nil {
			ruleTags, _ := a.Rule.GetTags()

			d.SarifIdentifier = a.Rule.SarifIdentifier
			d.RuleName = a.Rule.Name
			d.ShortDescription = a.Rule.ShortDescription
			d.FullDescription = a.Rule.FullDescription
			d.Help = a.Rule.Help
			d.Tags = ruleTags

			tool := a.Rule.Tool
			if tool != nil {
				d.Tool = tool.CanonicalName.String()
				if !tool.IsInternalGUID {
					d.ToolGUID = tool.GUID
				}
			}
		}

		if len(a.Links) > 0 {
			d.HasLinks = true
		}

		d.InsightsUpdatedAt = d.UpdatedAt

		// Autofix metadata
		d.AutofixEligible = a.AutofixEligible
		if a.SuggestedFixAlert != nil {
			d.AutofixState = a.SuggestedFixAlert.State.DBString()
			d.AutofixStateUpdatedAt = &a.SuggestedFixAlert.StateUpdatedAt
			d.AutofixAccepted = a.SuggestedFixAlert.WasSuggestionUsed()

			if a.SuggestedFixAlert.StateUpdatedAt.After(d.InsightsUpdatedAt.Time) {
				d.InsightsUpdatedAt = &a.SuggestedFixAlert.StateUpdatedAt
			}

			// We use the updated_at from the SFA to approximate when the suggestion_usage was updated
			if a.SuggestedFixAlert.UpdatedAt.After(d.InsightsUpdatedAt.Time) {
				d.InsightsUpdatedAt = &a.SuggestedFixAlert.UpdatedAt
			}
		}

		// Security campaigns
		d.SecurityCampaignIDs = transforms.Map(a.SecurityCampaignAlerts, func(sca *SecurityCampaignAlert) string {
			return fmt.Sprint(sca.SecurityCampaignID)
		})

		canonical, err := a.Canonical()
		if err == nil {
			// We only populate physical-related fields if we have a canonical alert for current configuration
			// (which should include only the default ref)
			d.CanonicalID = fmt.Sprint(canonical.ID)
			d.FixedOnDefault = a.IsFixed
			d.FixedAt = a.GetFixedAt()
		}

		if a.SecuritySeverityLevel() != proto.SecuritySeverity_NO_SECURITY_SEVERITY {
			severity = a.SecuritySeverityLevel().String()
		} else {
			severity = strings.ToUpper(a.SeverityLevel.String())
		}
		d.Severity = severity
		d.OwnerID = fmt.Sprint(repository.OwnerID)
		d.CodeScanningEnabled = &repository.CodeScanningEnabled
		if repository.Visibility.Valid {
			d.Visibility = repository.Visibility.String
		} else {
			d.Visibility = ""
		}

		docs = append(docs, d)
	}
	return docs, nil
}

func setLastStateChangeAt(a *LogicalAlert) (*LogicalAlert, error) {
	switch {
	case a.ResolvedAt != nil:
		a.LastStateChangeAt = a.ResolvedAt
	case len(a.PhysicalAlerts) == 0:
		a.LastStateChangeAt = &a.UpdatedAt
	case a.LastStateChangeAt != nil:
		// already set, do nothing
	default:
		maxTime := sqltime.Time{}
		for _, pa := range a.PhysicalAlerts {
			if pa.LastStateChangeAt.After(maxTime.Time) {
				maxTime = pa.LastStateChangeAt
			}
		}
		a.LastStateChangeAt = &maxTime
	}

	if a.LastStateChangeAt == nil || a.LastStateChangeAt.Time.Equal(sqltime.Time{}.Time) {
		return nil, errors.New("invalid LastStateChangeAt for logical alert")
	}
	return a, nil
}

// CalculateAlertClosure calculates if alert is closed on default ref and the timestamp of the alert closure, if any.
func (d *SearchDocument) CalculateAlertClosure() (bool, *timestamp.Timestamp) {
	var closedAtTimestamp *timestamp.Timestamp
	if d.FixedAt != nil {
		closedAtTimestamp = &timestamp.Timestamp{Seconds: d.FixedAt.Unix(), Nanos: int32(d.FixedAt.Nanosecond())}
	}

	if d.ResolvedAt != nil &&
		(d.Resolved != nil && *d.Resolved) &&
		(closedAtTimestamp == nil || d.ResolvedAt.After(closedAtTimestamp.AsTime())) {
		closedAtTimestamp = &timestamp.Timestamp{Seconds: d.ResolvedAt.Unix(), Nanos: int32(d.ResolvedAt.Nanosecond())}
	}

	// We can't only rely on 'closedAtTimestamp' being set to determine if an alert is closed
	// because fixed older alerts may not have 'FixedAt' set. Instead, we check 'FixedOnDefault'.
	// github/code-scanning#5777
	fixed := d.FixedOnDefault != nil && *d.FixedOnDefault
	closed := fixed || closedAtTimestamp != nil
	return closed, closedAtTimestamp
}

// HasAutofix returns true if the alert has a valid autofix.
func (d *SearchDocument) HasAutofix() bool {
	for _, state := range SuggestedFixAlertStateValidStates {
		if d.AutofixState == state.DBString() {
			return true
		}
	}

	return false
}
