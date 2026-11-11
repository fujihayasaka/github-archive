package eventpublisher

// AlertStatusChangedOption configures optional fields for PublishAlertStatusChanged.
//
// This uses the functional-options pattern so call sites only specify rarely-used
// fields (e.g. closure user) when relevant.
type AlertStatusChangedOption func(*alertStatusChangedOptions)

type alertStatusChangedOptions struct {
	closureUserID *uint64
	userID        *uint64
	comment       *string
}

// WithClosureEventUserID sets the user ID to populate in the Hydro
// LicenseComplianceAlertStatusChanged.ClosureUserId field.
func WithClosureEventUserID(userID *uint64) AlertStatusChangedOption {
	return func(o *alertStatusChangedOptions) {
		o.closureUserID = userID
	}
}

// WithUserID sets the user ID to populate in the Hydro
// LicenseComplianceAlertStatusChanged.UserId field.
func WithUserID(userID *uint64) AlertStatusChangedOption {
	return func(o *alertStatusChangedOptions) {
		o.userID = userID
	}
}

// WithComment sets the comment to populate in the Hydro
// LicenseComplianceAlertStatusChanged.Comment field.
func WithComment(comment *string) AlertStatusChangedOption {
	return func(o *alertStatusChangedOptions) {
		o.comment = comment
	}
}
