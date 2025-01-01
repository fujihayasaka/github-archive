package ts

import (
	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

var (
	ErrCodeqlRepoNotEnabled = errors.New("default setup is not enabled")
)

// CodeqlRepo represents the default setup state of a repository
type CodeqlRepo struct {
	BaseModel
	ID            CodeqlRepoID
	EnabledAt     sqltime.Time
	SoftDeletedAt *sqltime.Time

	RepositoryID   RepositoryEID
	RepositoryGRID RepositoryGRID `gorm:"column:repository_grid"`

	// Repo properties
	SupportedLanguages     Languages
	UsingCombinedLanguages bool

	// Configuration details for the repo.
	QuerySuite              QuerySuite
	ThreatModel             ThreatModel
	RunnerLabel             string
	JavaExtractionOptions   JavaExtractionOptions
	CSharpExtractionOptions CSharpExtractionOptions `gorm:"column:csharp_extraction_options"`
	CppExtractionOptions    CppExtractionOptions

	EnabledByActorLogin string

	// Codeql Configurations
	CurrentConfigID *CodeqlConfigID
	CurrentConfig   *CodeqlConfig `gorm:"foreignKey:CurrentConfigID"`

	StagedConfigID *CodeqlConfigID
	StagedConfig   *CodeqlConfig `gorm:"foreignKey:StagedConfigID"`

	// Latest configuration that failed the validation run.
	// Only exists if the latest validation run failed.
	FailedConfigID *CodeqlConfigID
	FailedConfig   *CodeqlConfig `gorm:"foreignKey:FailedConfigID"`
}

type DisabledCodeqlRepo struct {
	RepositoryID RepositoryEID
	DisabledAt   sqltime.Time `gorm:"column:soft_deleted_at"`
}

type CodeqlRepoID uint64

// OnboardingStatus represents the onboarding status of a repository.
type OnboardingStatus uint8

const (
	OnboardingStatus_DISABLED OnboardingStatus = iota
	OnboardingStatus_WAITING
	OnboardingStatus_ONBOARDING
	OnboardingStatus_STABLE
	OnboardingStatus_UPDATING
)

func (r *CodeqlRepo) OnboardingStatus() OnboardingStatus {
	switch {
	case r.SoftDeletedAt != nil:
		return OnboardingStatus_DISABLED
	case r.CurrentConfig == nil && r.StagedConfig == nil:
		return OnboardingStatus_WAITING
	case r.CurrentConfig == nil && r.StagedConfig != nil:
		return OnboardingStatus_ONBOARDING
	case r.CurrentConfig != nil && r.StagedConfig == nil:
		return OnboardingStatus_STABLE
	case r.CurrentConfig != nil && r.StagedConfig != nil:
		return OnboardingStatus_UPDATING
	default:
		panic("unreachable")
	}
}

// IsEnabled returns true if the repository is enabled
func (r *CodeqlRepo) IsEnabled() bool {
	return r.OnboardingStatus() != OnboardingStatus_DISABLED
}

// IsOnboarded returns true if the repository is onboarded
func (r *CodeqlRepo) IsOnboarded() bool {
	status := r.OnboardingStatus()
	return status == OnboardingStatus_STABLE || status == OnboardingStatus_UPDATING
}

// IsOnboarding returns true if the repository is onboarding
func (r *CodeqlRepo) IsOnboarding() bool {
	return r.OnboardingStatus() == OnboardingStatus_ONBOARDING
}

// IsUpdating returns true if the repository is updating
func (r *CodeqlRepo) IsUpdating() bool {
	return r.OnboardingStatus() == OnboardingStatus_UPDATING
}

// IsWaiting returns true if the repository is waiting
func (r *CodeqlRepo) IsWaiting() bool {
	return r.OnboardingStatus() == OnboardingStatus_WAITING
}

// IsStable returns true if the repository is stable
func (r *CodeqlRepo) IsStable() bool {
	return r.OnboardingStatus() == OnboardingStatus_STABLE
}

// HasFailedUpdate returns true if the repository is onboarded but a config update has failed "recently"
func (r *CodeqlRepo) HasFailedUpdate() bool {
	debuggable := r.DebuggableConfig()
	return r.IsOnboarded() && debuggable != nil && debuggable.IsDeprecated()
}

// DebuggableConfig returns the latest CodeQL config whose validation run
// the user may want to look into.
// This can be the first config that gets validated after enabling managed analysis
// (not necessarily for the first time).
// It can also be a config for a config update or a workflow template upgrade.
func (r *CodeqlRepo) DebuggableConfig() *CodeqlConfig {
	// If there's a staged config then that's definitely the one we want!
	if r.StagedConfig != nil {
		return r.StagedConfig
	}

	// Our next candidate is FailedConfig
	if r.FailedConfig != nil {
		return r.FailedConfig
	}

	// If we get here, we have excluded that there was an error in previous configs that is worth showing.
	// Therefore, if there is a current config, we return that as it might include information about
	// various adjustments we performed.
	return r.CurrentConfig // may be nil
}

// BeforeSave is a gorm hook that is called before saving a CodeqlRepo
func (r *CodeqlRepo) BeforeSave(scope *gorm.Scope) error {
	// Never update the value of UsingCombinedLanguages. This value is set to true for newer repos in the DB schema.
	// We want to preserve the existing value for existing repos, and avoid accidental changes.
	scope.Search.Omit(append(scope.OmitAttrs(), "UsingCombinedLanguages")...)

	// Check that the IDs are set correctly
	if r.CurrentConfig != nil && r.CurrentConfig.ID != 0 &&
		r.CurrentConfigID != nil && *r.CurrentConfigID != r.CurrentConfig.ID {
		return errors.Errorf("CurrentConfigID %d does not match CurrentConfig.ID %d", r.CurrentConfigID, r.CurrentConfig.ID)
	}

	if r.StagedConfig != nil && r.StagedConfig.ID != 0 &&
		r.StagedConfigID != nil && *r.StagedConfigID != r.StagedConfig.ID {
		return errors.Errorf("StagedConfigID %d does not match StagedConfig.ID %d", r.StagedConfigID, r.StagedConfig.ID)
	}

	if r.FailedConfig != nil && r.FailedConfig.ID != 0 &&
		r.FailedConfigID != nil && *r.FailedConfigID != r.FailedConfig.ID {
		return errors.Errorf("FailedConfigID %d does not match FailedConfig.ID %d", r.FailedConfigID, r.FailedConfig.ID)
	}

	return nil
}

// BeforeCreate is a gorm hook that is called before creating a CodeqlRepo
func (r *CodeqlRepo) BeforeCreate(scope *gorm.Scope) error {
	// Make sure that EnabledAt has a correct value
	if r.EnabledAt.IsZero() {
		r.EnabledAt = sqltime.Now()
	}

	return nil
}
