package resolver

type Config struct {
	AppID             int64  `config:"0,env=ACTIONS_RESOLVER_APP_ID"`
	AppInstallationID int64  `config:"0,env=ACTIONS_RESOLVER_APP_INSTALLATION_ID"`
	AppPrivateKey     string `config:",env=ACTIONS_RESOLVER_APP_PRIVATE_KEY"`
}
