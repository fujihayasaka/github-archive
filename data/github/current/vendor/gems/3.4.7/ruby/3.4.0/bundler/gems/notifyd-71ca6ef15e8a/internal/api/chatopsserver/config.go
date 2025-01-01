package chatopsserver

// Config represents the configuration for the chatops server.
type Config struct {
	Enabled      bool   `config:"false,env=CHATOPS_ENABLED"`
	Addr         string `config:":8082,env=CHATOPS_ADDR"`
	BaseURL      string `config:"http://localhost:8082,env=CHATOPS_BASE_URL"`
	BotPublicKey string `config:",env=CHATOPS_BOT_PUBLIC_KEY"`
}
