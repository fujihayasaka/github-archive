package skills

// Metadata contains information about where a skill came from.
type Metadata struct {
	Name        string // Directory name (slug) - used for API lookups
	RepoID      int64
	RepoOwner   string
	RepoOwnerID int64
	RepoName    string
	Version     string // Git SHA
	FilePath    string // Relative path to SKILL.md (e.g., ".github/skills/my-skill/SKILL.md")
}

// Config holds the parsed skill configuration from SKILL.md frontmatter.
type Config struct {
	Name                   string
	Description            string
	AllowedTools           []string
	UserInvocable          bool
	DisableModelInvocation bool
	Content                string
}

// Skill represents a fully loaded skill definition.
type Skill struct {
	metadata Metadata
	config   *Config
}

// NewSkill creates a new Skill for testing purposes.
func NewSkill(metadata Metadata, description, content string, allowedTools []string, disableModelInvocation, userInvocable bool) *Skill {
	return &Skill{
		metadata: metadata,
		config: &Config{
			Name:                   metadata.Name,
			Description:            description,
			Content:                content,
			AllowedTools:           allowedTools,
			DisableModelInvocation: disableModelInvocation,
			UserInvocable:          userInvocable,
		},
	}
}

// Name returns the skill's directory name, used for API lookups.
// This is always the directory name, regardless of frontmatter.
func (s *Skill) Name() string {
	return s.metadata.Name
}

// DisplayName returns the skill's display name for UI purposes.
// Prefers frontmatter name if provided, otherwise uses directory name.
// IMPORTANT: This is the name of the skill in the skill tool so we must de-dupe on this (based on CLI)
func (s *Skill) DisplayName() string {
	if s.config != nil && s.config.Name != "" {
		return s.config.Name
	}
	return s.metadata.Name
}

// FilePath returns the relative path to the SKILL.md file.
func (s *Skill) FilePath() string {
	return s.metadata.FilePath
}

// Description returns what the skill does.
func (s *Skill) Description() string {
	if s.config != nil {
		return s.config.Description
	}
	return ""
}

// RepoOwner returns the repository owner where the skill is defined.
func (s *Skill) RepoOwner() string {
	return s.metadata.RepoOwner
}

// RepoName returns the repository name where the skill is defined.
func (s *Skill) RepoName() string {
	return s.metadata.RepoName
}

// RepoID returns the repository ID.
func (s *Skill) RepoID() int64 {
	return s.metadata.RepoID
}

// RepoOwnerID returns the repository owner ID.
func (s *Skill) RepoOwnerID() int64 {
	return s.metadata.RepoOwnerID
}

// Version returns the git SHA of the skill source.
func (s *Skill) Version() string {
	return s.metadata.Version
}

// Content returns the full SKILL.md content.
func (s *Skill) Content() string {
	if s.config != nil {
		return s.config.Content
	}
	return ""
}

// AllowedTools returns the tools auto-allowed when skill is active.
func (s *Skill) AllowedTools() []string {
	if s.config != nil {
		return s.config.AllowedTools
	}
	return nil
}

// UserInvocable returns whether user can invoke as slash command.
func (s *Skill) UserInvocable() bool {
	if s.config != nil {
		return s.config.UserInvocable
	}
	return true // Default to true
}

// DisableModelInvocation returns whether model is prevented from invoking.
func (s *Skill) DisableModelInvocation() bool {
	if s.config != nil {
		return s.config.DisableModelInvocation
	}
	return false // Default to false
}
