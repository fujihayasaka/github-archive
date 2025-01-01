package selectors

func NewQuarantineObjectsSelector() *QuarantineObjectsSelector {
	return &QuarantineObjectsSelector{}
}

func (p *QuarantineObjectsSelector) Validate() error {
	return nil
}
