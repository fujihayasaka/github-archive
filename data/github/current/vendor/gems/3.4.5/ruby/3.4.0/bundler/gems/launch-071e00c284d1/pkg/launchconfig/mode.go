package launchconfig

// AppMode defines our application mode (e.g., enterprise)
type AppMode string

const (
	HostedAppMode     AppMode = "hosted"
	EnterpriseAppMode AppMode = "enterprise"
)

func (mode AppMode) String() string {
	return string(mode)
}

func ParseMode(input string) AppMode {
	if input == "enterprise" {
		return EnterpriseAppMode
	}

	return HostedAppMode
}
