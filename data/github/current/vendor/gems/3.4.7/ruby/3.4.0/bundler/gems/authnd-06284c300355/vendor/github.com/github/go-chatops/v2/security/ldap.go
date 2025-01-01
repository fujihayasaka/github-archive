package security

import (
	"fmt"
	"io/ioutil"

	ldap "github.com/parkr/go-ldap-client"
	yaml "gopkg.in/yaml.v2"
)

/*
These functions handle loading and configuring an LDAP client from a configuration
file.  There's no reason the client cannot be configured directly, but there are
few cases where hard-coding ldap connection values in the code make sense.  Mostly
these values should be loaded from a config file.

This will handle a yaml file with the following format:

---
base: dc=example,dc=net
host: ldap.example.net
port: 636
usessl: true
binddn: uid=readonlyuser,ou=Service_Accounts,dc=example,dc=net
userfilter: "(&(objectClass=organizationalPerson)(uid=%s))"
groupfilter: "(uniqueMember=uid=%s,ou=People,dc=example,dc=net)"
attributes:
  - sn
  - cn
  - uid

Please do not store the password in a config file!  Load it from a source
which isn't stored on disk!

**/

// LDAPConfig holds data from a yaml file about our ldap connection.
type LDAPConfig struct {
	Base         string
	Host         string
	Port         int
	UseSSL       bool
	BindDN       string
	BindPassword string
	UserFilter   string
	GroupFilter  string
	Attributes   []string
}

// InitializeLDAPClient opens a config file with the ldap info an initializes a new client object.
func InitializeLDAPClient(filename, password string) (*ldap.LDAPClient, error) {
	rawConfig, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("unable to read ldap config from file %s: %w", filename, err)
	}

	var config LDAPConfig
	err = yaml.Unmarshal(rawConfig, &config)
	if err != nil {
		return nil, fmt.Errorf("error unmarshalling YAML in InitializeLDAPClient from string %s: %w", rawConfig, err)
	}

	config.BindPassword = password

	// create the client
	return &ldap.LDAPClient{
		Base:         config.Base,
		Host:         config.Host,
		Port:         config.Port,
		UseSSL:       config.UseSSL,
		ServerName:   config.Host,
		BindDN:       config.BindDN,
		BindPassword: config.BindPassword,
		UserFilter:   config.UserFilter,
		GroupFilter:  config.GroupFilter,
		Attributes:   config.Attributes,
	}, nil
}
