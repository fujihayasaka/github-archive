package selectors

func NewUniversalSelector() *UniversalSelector {
	return &UniversalSelector{}
}

func (u *UniversalSelector) Validate() error {
	return nil
}
