package email

// Config represents SMTP configuration.
type Config struct {
	Host     string `config:",env=NOTIFYD_SMTP_HOST,required"`
	Port     string `config:",env=NOTIFYD_SMTP_PORT,required"`
	UseTLS   bool   `config:"true,env=NOTIFYD_SMTP_USE_TLS"`
	UseAuth  bool   `config:"true,env=NOTIFYD_SMTP_USE_AUTH"`
	Username string `config:",env=GLB_BALANCED_MAIL_SMTP_USER,required"`
	Password string `config:",env=GLB_BALANCED_MAIL_SMTP_PASSWORD,required"`
}
