package skills

// SkillDTO is the JSON representation of a skill for API responses.
// Used by both the skills HTTP API and the agent HTTP API.
type SkillDTO struct {
	Name                   string   `json:"name"`         // Slug (directory name) - used for API lookups
	DisplayName            string   `json:"display_name"` // User-friendly name from frontmatter
	Description            string   `json:"description"`
	RepoOwnerID            int64    `json:"repo_owner_id"`
	RepoOwner              string   `json:"repo_owner"`
	RepoID                 int64    `json:"repo_id"`
	RepoName               string   `json:"repo_name"`
	Version                string   `json:"version"`
	FilePath               string   `json:"file_path"`         // Relative path to SKILL.md
	Content                string   `json:"content,omitempty"` // Only included in single get
	AllowedTools           []string `json:"allowed_tools,omitempty"`
	UserInvocable          bool     `json:"user_invocable"`
	DisableModelInvocation bool     `json:"disable_model_invocation"`
}

// MakeSkillDTO converts a Skill to a SkillDTO.
// includeContent controls whether the full Content is included (only for single-skill get).
func MakeSkillDTO(skill *Skill, includeContent bool) SkillDTO {
	dto := SkillDTO{
		Name:                   skill.Name(),
		DisplayName:            skill.DisplayName(),
		Description:            skill.Description(),
		RepoOwnerID:            skill.RepoOwnerID(),
		RepoOwner:              skill.RepoOwner(),
		RepoID:                 skill.RepoID(),
		RepoName:               skill.RepoName(),
		Version:                skill.Version(),
		FilePath:               skill.FilePath(),
		AllowedTools:           skill.AllowedTools(),
		UserInvocable:          skill.UserInvocable(),
		DisableModelInvocation: skill.DisableModelInvocation(),
	}

	if includeContent {
		dto.Content = skill.Content()
	}

	return dto
}
