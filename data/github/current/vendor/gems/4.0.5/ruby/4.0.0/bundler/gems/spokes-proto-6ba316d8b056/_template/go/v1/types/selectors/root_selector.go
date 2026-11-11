package selectors

func NewRootSelector() *RootSelector {
	return &RootSelector{}
}

func (r *RootSelector) Validate() error {
	return nil
}
