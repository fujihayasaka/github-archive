package prompt

type SystemTemplateArguments struct {
	UseReplacementBlocks bool
}

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
