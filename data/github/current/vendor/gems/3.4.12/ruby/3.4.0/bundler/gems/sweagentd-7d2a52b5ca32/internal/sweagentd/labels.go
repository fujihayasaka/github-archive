package sweagentd

type LabelMetadata struct {
	Labels        []string
	CopilotLabels []string
	CustomAgent   string
	Model         string
}

const (
	CopilotLabelPrefix = "copilot:"
	ModelLabelPrefix   = CopilotLabelPrefix + "agent="
)

func (m LabelMetadata) HasModel() bool {
	return m.Model != ""
}

func (m LabelMetadata) HasCopilotLabels() bool {
	return len(m.CopilotLabels) > 0
}
