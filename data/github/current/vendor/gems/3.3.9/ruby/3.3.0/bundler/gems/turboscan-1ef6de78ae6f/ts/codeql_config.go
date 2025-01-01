package ts

import (
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts/gormext"
	"go.uber.org/zap/zapcore"

	"github.com/pkg/errors"
)

var (
	ErrCodeqlConfigNotFound = errors.New("codeql config not found")
	ErrCodeqlConfigConflict = errors.New("a new configuration is already being staged")
	ErrNoChangeRequired     = errors.New("no change required")
)

// CodeqlConfig represents the configuration for managed analysis for a specific repository,
// including whether the analysis needs to run and how.
type CodeqlConfig struct {
	BaseModel
	ID CodeqlConfigID

	RepositoryID   RepositoryEID
	RepositoryGRID RepositoryGRID `gorm:"column:repository_grid"`

	// Configuration details for the repo.
	Languages               Languages
	InitialLanguages        Languages
	QuerySuiteType          QuerySuiteType
	ThreatModel             ThreatModel
	UsingCombinedLanguages  bool
	UsingCSRunnerLabel      bool
	RunnerLabel             string
	JavaExtractionOptions   JavaExtractionOptions
	CSharpExtractionOptions CSharpExtractionOptions `gorm:"column:csharp_extraction_options"`

	// Final status of the Run.
	// This is populated only after we received confirmation that the run is completed|failed|cancelled
	ValidationRunStatus *CodeqlRunStatus
	DeprecatedAt        *sqltime.Time
	EnabledAt           *sqltime.Time

	OnboardedByActorGRID ActorGRID `gorm:"column:onboarded_by_actor_grid"`
	CreatedByActorLogin  string

	// The validated workflow for the Repo
	Workflow string

	TemplateVersion string
	Tag             *CodeqlConfigTag `gorm:"default:0"`

	// Associations
	ValidationRun *CodeqlRun
	LatestRun     *CodeqlRun
}

type CodeqlConfigID uint64

func (c CodeqlConfigID) AsKVP() zapcore.Field {
	return kvp.Uint64("gh.turboscan.codeql_config_id", uint64(c))
}

type CodeqlConfigTag uint8

const (
	CodeqlConfigTag_CURRENT CodeqlConfigTag = iota
	CodeqlConfigTag_STAGED
)

// Deprecate sets CodeqlConfig Tag to nil
func (c *CodeqlConfig) Deprecate() *CodeqlConfig {
	c.Tag = nil
	now := time.Now()
	c.DeprecatedAt = gormext.ConvertTime(&now)
	return c
}

// MakeCurrent sets CodeqlConfig Tag to current
func (c *CodeqlConfig) MakeCurrent() *CodeqlConfig {
	newTag := CodeqlConfigTag_CURRENT
	c.Tag = &newTag
	return c
}

// MakeStaged sets CodeqlConfig Tag to staged
func (c *CodeqlConfig) MakeStaged() *CodeqlConfig {
	newTag := CodeqlConfigTag_STAGED
	c.Tag = &newTag
	return c
}

// IsStaged gets the value of CodeqlConfig's Tag and returns true if staged
func (c *CodeqlConfig) IsStaged() bool {
	return c.Tag != nil && *c.Tag == CodeqlConfigTag_STAGED
}

// IsCurrent gets the value of CodeqlConfig's Tag and returns true if current
func (c *CodeqlConfig) IsCurrent() bool {
	return c.Tag != nil && *c.Tag == CodeqlConfigTag_CURRENT
}

// IsDeprecated gets the value of CodeqlConfig's Tag and returns true if nil
func (c *CodeqlConfig) IsDeprecated() bool {
	return c.Tag == nil
}

func (c *CodeqlConfig) ValidationCompleted() bool {
	return c.ValidationRunStatus != nil &&
		*c.ValidationRunStatus == CodeqlRunStatus_COMPLETED
}

type WorkflowTemplate interface {
	CodeQLWorkflow(*CodeqlConfig) (string, error)
	CodeQLValidationWorkflow(*CodeqlConfig, bool) (string, error)
	GetVersion() string
}

// SetUpForValidationRun prepares the CodeqlConfig for a validation run.
// This changes the Tag to STAGED, and the TemplateVersion to that of
// the supplied WorkflowTemplate. It sets a steady state workflow and
// returns the CodeqlRun to use for validation.
func (c *CodeqlConfig) SetUpForValidationRun(ref Ref, sha Sha, wt WorkflowTemplate, e CodeqlRunTriggeringEvent,
	ownerID OwnerEID, codeqlPacks CodeqlPacks) (*CodeqlRun, error) {
	return c.setUpForValidationRun(ref, sha, wt, e, ownerID, codeqlPacks, false)
}

// SetUpForValidationRunWithAutoAdjust prepares the CodeqlConfig for a validation run.
// Differently from SetUpForValidationRun, this method will try to adjust the configuration
// if some (but not all) of the jobs in the workflow fail.
func (c *CodeqlConfig) SetUpForValidationRunWithAutoAdjust(ref Ref, sha Sha, wt WorkflowTemplate, e CodeqlRunTriggeringEvent,
	ownerID OwnerEID, codeqlPacks CodeqlPacks) (*CodeqlRun, error) {
	return c.setUpForValidationRun(ref, sha, wt, e, ownerID, codeqlPacks, true)
}

func (c *CodeqlConfig) setUpForValidationRun(ref Ref, sha Sha, wt WorkflowTemplate, e CodeqlRunTriggeringEvent,
	ownerID OwnerEID, codeqlPacks CodeqlPacks, autoAdjustConfig bool) (*CodeqlRun, error) {
	validationW, err := wt.CodeQLValidationWorkflow(c, autoAdjustConfig)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create workflow for CodeQL")
	}

	run, err := newCodeqlRun(c, c.OnboardedByActor(), ref, sha, validationW, e, CodeqlRunType_VALIDATION, true, ownerID, codeqlPacks, nil)
	if err != nil {
		return nil, errors.Wrap(err, "failed to build a run")
	}

	steadyW, err := wt.CodeQLWorkflow(c)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create workflow for CodeQL")
	}

	// Set steady state workflow and onboarding status
	c.Workflow = steadyW
	c.TemplateVersion = wt.GetVersion()
	c.MakeStaged()

	return run, nil
}

// NewRun returns a new CodeqlRun to be run. This is a SteadyState run, so the workflow is the one in the configuration.
func (c *CodeqlConfig) NewRun(actor *ActorGRIDLogin, ref Ref, sha Sha, e CodeqlRunTriggeringEvent, defaultBranch bool,
	ownerID OwnerEID, codeqlPacks CodeqlPacks, eventTimeStamp *sqltime.Time) (*CodeqlRun, error) {
	return newCodeqlRun(c, actor, ref, sha, c.Workflow, e, CodeqlRunType_STEADY, defaultBranch, ownerID, codeqlPacks, eventTimeStamp)
}

func (c *CodeqlConfig) BeforeCreate() error {
	if c.RepositoryID == 0 {
		return errors.New("RepositoryID cannot be zero")
	}

	return nil
}

func (c *CodeqlConfig) CopyForUpdate() *CodeqlConfig {
	return &CodeqlConfig{
		RepositoryID:   c.RepositoryID,
		RepositoryGRID: c.RepositoryGRID,
		// Repo-level options
		UsingCombinedLanguages:  c.UsingCombinedLanguages,
		UsingCSRunnerLabel:      c.UsingCSRunnerLabel,
		RunnerLabel:             c.RunnerLabel,
		JavaExtractionOptions:   c.JavaExtractionOptions,
		CSharpExtractionOptions: c.CSharpExtractionOptions,
		TemplateVersion:         c.TemplateVersion,
		// Config values
		InitialLanguages: NormalizeLanguages(c.InitialLanguages),   // We use NormalizeLanguages to force a copy
		Languages:        NormalizeLanguages(c.Languages),          //
		QuerySuiteType:   c.QuerySuiteType.Root().QuerySuiteType(), // Force a copy
		ThreatModel:      c.ThreatModel,
	}
}

func (c *CodeqlConfig) NewUpdatedConfig(
	// New Config Values
	newSelectedLanguages Languages,
	newQuerySuite QuerySuite,
	newThreatModel ThreatModel,
	newUseCodeScanningRunnerLabel bool,
	newRunnerLabel string,
	// Who triggered the update
	actor *ActorGRIDLogin,
) *CodeqlConfig {
	out := c.CopyForUpdate()

	// New config values
	out.InitialLanguages = NormalizeLanguages(newSelectedLanguages)
	out.Languages = NormalizeLanguages(newSelectedLanguages)
	out.QuerySuiteType = newQuerySuite.QuerySuiteType()
	out.ThreatModel = newThreatModel
	out.RunnerLabel = newRunnerLabel
	out.UsingCSRunnerLabel = newUseCodeScanningRunnerLabel

	// OnboardedBy
	out.OnboardedByActorGRID = actor.GRID
	out.CreatedByActorLogin = actor.Login

	return out
}

// IsEquivalent returns true if the configurable fields of the two configurations are the same
func (c *CodeqlConfig) IsEquivalent(other *CodeqlConfig) bool {
	return c.RepositoryID == other.RepositoryID &&
		c.RepositoryGRID == other.RepositoryGRID &&
		// Repo-level options
		c.UsingCombinedLanguages == other.UsingCombinedLanguages &&
		c.UsingCSRunnerLabel == other.UsingCSRunnerLabel &&
		c.RunnerLabel == other.RunnerLabel &&
		c.JavaExtractionOptions == other.JavaExtractionOptions &&
		c.CSharpExtractionOptions == other.CSharpExtractionOptions &&

		// Config values
		c.InitialLanguages.Equals(other.InitialLanguages) &&
		c.Languages.Equals(other.Languages) &&
		c.QuerySuiteType.Equals(other.QuerySuiteType) &&
		c.ThreatModel == other.ThreatModel
}

func (c *CodeqlConfig) OnboardedByActor() *ActorGRIDLogin {
	return &ActorGRIDLogin{
		GRID:  c.OnboardedByActorGRID,
		Login: c.CreatedByActorLogin,
	}
}

// JavaExtractionOptions represents the options for Java extraction.
// Currently supports only whether the extraction is traced or buildless.
type JavaExtractionOptions uint8

const (
	JavaExtractionOptions_TRACED JavaExtractionOptions = iota
	JavaExtractionOptions_BUILDLESS
)

// CSharpExtractionOptions represents the options for C# extraction.
// Currently supports only whether the extraction is traced or buildless.
type CSharpExtractionOptions uint8

const (
	CSharpExtractionOptions_TRACED CSharpExtractionOptions = iota
	CSharpExtractionOptions_BUILDLESS
)
