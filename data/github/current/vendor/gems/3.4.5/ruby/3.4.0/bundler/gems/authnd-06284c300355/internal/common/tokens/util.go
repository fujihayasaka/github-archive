package tokens

import (
	"crypto/sha256"
	"encoding/base64"
	"regexp"
)

type TokenType uint

func (t TokenType) String() string {
	switch t {
	case LegacyPersonalAccessToken:
		return "LegacyPersonalAccessToken"
	case FineGrainedPersonalAccessToken:
		return "FineGrainedPersonalAccessToken"
	case OAuthAppToken:
		return "OAuthAppToken"
	case GitHubAppUserToServerToken:
		return "GitHubAppUserToServerToken"
	case GitHubAppServerToServerToken:
		return "GitHubAppServerToServerToken"
	default:
		return "UnknownToken"
	}
}

const (
	UnknownToken TokenType = iota
	LegacyPersonalAccessToken
	FineGrainedPersonalAccessToken
	OAuthAppToken
	GitHubAppUserToServerToken
	GitHubAppServerToServerToken
)

// TODO(chriskirkland): deduplicate this from the client (clients/tokens.go)
var fineGrainedPersonalAccessTokenRegex = regexp.MustCompile(`^(gh1_[A-Za-z0-9]{21}_[A-Za-z0-9]{59}|github_pat_[0-9][A-Za-z0-9]{21}_[A-Za-z0-9]{59})$`)

var oauthAppTokenRegex = regexp.MustCompile(`^(gho_[a-zA-Z0-9]{36}|[a-f0-9]{40})$`)
var legacyPersonalAccessTokenRegex = regexp.MustCompile(`^ghp_[a-zA-Z0-9]{36}$`)
var githubAppUserToServerTokenRegex = regexp.MustCompile(`^ghu_[a-zA-Z0-9]{36}$`)

// # Public: The Regexp describing the format of an AuthenticationToken's string
// # token value.
//
//	TOKEN_PATTERN_GS1 = %r{
//	  \A                              # start
//	  #{self.access_token_prefix}     # the token format prefix
//	  [a-zA-Z0-9]{36}                 # the random portion and checksum
//	  \z                              # end
//	}xi
//
// # legacy pattern
//
//	TOKEN_PATTERN_V1 = %r{
//	  \A                 # start
//	  v1                 # the token format version
//	  \.                 # a period
//	  [a-f0-9]{40}       # the random portion of the token
//	  \z                 # end
//	}xi
var authenticationTokenRegex = regexp.MustCompile(`^(ghs_[a-zA-Z0-9]{36}|v1.[a-f0-9]{40})$`)

// GetTokenType returns the TokenType for the provided token based on all known token formats
func GetTokenType(token string) TokenType {
	if fineGrainedPersonalAccessTokenRegex.MatchString(token) {
		return FineGrainedPersonalAccessToken
	} else if legacyPersonalAccessTokenRegex.MatchString(token) {
		return LegacyPersonalAccessToken
	} else if oauthAppTokenRegex.MatchString(token) {
		return OAuthAppToken
	} else if githubAppUserToServerTokenRegex.MatchString(token) {
		return GitHubAppUserToServerToken
	} else if authenticationTokenRegex.MatchString(token) {
		return GitHubAppServerToServerToken
	} else {
		return UnknownToken
	}
}

// returns the last 8 characters of a token
func LastEight(token string) string {
	if len(token) < 8 {
		return token
	}
	return token[len(token)-8:]
}

func Prefix(token string) string {
	if len(token) < 3 {
		return token
	}
	return token[:3]
}

// returns the base64-encoded sha256 hash of the provided value
func Hash(token string) string {
	hash := sha256.Sum256([]byte(token))
	return base64.StdEncoding.EncodeToString(hash[:])
}
