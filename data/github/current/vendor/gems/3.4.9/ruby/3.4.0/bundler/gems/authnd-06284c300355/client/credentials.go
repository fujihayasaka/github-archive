package client

import (
	pb "github.com/github/authnd/client/proto/authentication/v0"
)

// A Credentials object represents the credentials that will be provided to authnd to authenticate.
type Credentials struct {
	*pb.Credentials
}

// NewSSHKeyCredentials creates a Credentials for the provided SSH Public Key.
// The key must be in the "OpenSSH Authorized Keys" format.
func NewSSHKeyCredentials(key string) *Credentials {
	credential := &pb.Credentials{
		Kind: &pb.Credentials_SshPublicKey{
			SshPublicKey: &pb.SSHPublicKey{
				Key: key,
			},
		},
	}
	return credentials(credential)
}

// NewLoginPasswordCredentials creates a Credentials for the provided login and password pair.
func NewLoginPasswordCredentials(login string, password string) *Credentials {
	credential := &pb.Credentials{
		Kind: &pb.Credentials_LoginPassword{
			LoginPassword: &pb.LoginPassword{
				Login:    login,
				Password: password,
			},
		},
	}
	return credentials(credential)
}

// NewAccessTokenCredentials creates a Credentials for the provided Access Token.
func NewAccessTokenCredentials(token string) *Credentials {
	credential := &pb.Credentials{
		Kind: &pb.Credentials_AccessToken{
			AccessToken: &pb.AccessToken{
				Token: token,
			},
		},
	}
	return credentials(credential)
}

// NewSignedAuthTokenCredentials creates a Credentials for the provided Signed Auth Token (SAT).
// You must also provide the "scope" value that is shared between the code that generated the token and the code that is validating the token.
// See https://thehub.github.com/engineering/development-and-ops/secure-coding/secure-coding-dotcom/authn/#signed-auth-tokens for more information on SATs and scopes.
func NewSignedAuthTokenCredentials(token string, scope string) *Credentials {
	credential := &pb.Credentials{
		Kind: &pb.Credentials_SignedAuthToken{
			SignedAuthToken: &pb.SignedAuthToken{
				Token: token,
				Scope: scope,
			},
		},
	}
	return credentials(credential)
}

func credentials(credentials *pb.Credentials) *Credentials {
	return &Credentials{
		Credentials: credentials,
	}
}
