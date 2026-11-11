package selectors

func NewParentSelector() *ParentSelector {
	return &ParentSelector{}
}

func (p *ParentSelector) Validate() error {
	return nil
}
