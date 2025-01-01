package prompt

// SystemTemplateArguments supplies data to the autovalidate system prompt template.
type SystemTemplateArguments struct {
	UseReplacementBlocks bool
}

// BuildSystemPrompt renders the appropriate system prompt for reasoning or
// non-reasoning models optionally including replacement block instructions.
func BuildSystemPrompt(useReplacementBlocks bool, forReasoningModel bool) (string, error) {
	var templateName string
	if forReasoningModel {
		templateName = "system-reasoning-models.md"
	} else {
		templateName = "system-non-reasoning-models.md"
	}
	return ExecuteTemplate(templateName, SystemTemplateArguments{
		UseReplacementBlocks: useReplacementBlocks,
	}, nil)
}
