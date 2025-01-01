package selectors

func NewQuarantineCommitsSelector() *QuarantineCommitsSelector {
	return &QuarantineCommitsSelector{}
}

func (p *QuarantineCommitsSelector) Validate() error {
	return nil
}
