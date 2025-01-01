package tokens

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestTokenType(t *testing.T) {
	for _, tc := range []struct {
		token    string
		expected TokenType
	}{
		// legacy oauth app tokens
		{token: "104e4a74fd828b68be42b8f6dee9134ec174be77", expected: OAuthAppToken},
		{token: "47a9fb75a1f3226640ad149faf7166ac9688d2d8", expected: OAuthAppToken},
		{token: "9aa7585fc71ecc55c10c30e0d898953e165d711f", expected: OAuthAppToken},
		// modern oauth app tokens
		{token: "gho_872b79cb96c16e1834b6a2312688ef71b281", expected: OAuthAppToken},
		{token: "gho_572b79cb96c16e1834b6a2312688ef71b281", expected: OAuthAppToken},
		{token: "gho_892b79cb96c16e1834b6a2312688ef71b281", expected: OAuthAppToken},
		// legacy PATs
		{token: "ghp_492b79cb96c16e1834b6a2312688ef71b281", expected: LegacyPersonalAccessToken},
		{token: "ghp_1ecc7e327e384e0b8f2004834a2bfe8e00a9", expected: LegacyPersonalAccessToken},
		{token: "ghp_d6ce4c187111ead253992afcf4c6d6a2b627", expected: LegacyPersonalAccessToken},
		// fg PATs
		{token: "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", expected: FineGrainedPersonalAccessToken},
		{token: "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", expected: FineGrainedPersonalAccessToken},
		{token: "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", expected: FineGrainedPersonalAccessToken},
		// GitHub App user-to-server tokens
		{token: "ghu_992b79cb96c16e1834b6a2312688ef71b281", expected: GitHubAppUserToServerToken},
		{token: "ghu_192b79cb96c16e1834b6a2312688ef71b281", expected: GitHubAppUserToServerToken},
		{token: "ghu_102b79cb96c16e1834b6a2312688ef71b281", expected: GitHubAppUserToServerToken},
		// GitHub App server-to-server tokens
		{token: "ghs_yluBtAeLFkzhyXd2oByHyFy96ST3vX1S3aIj", expected: GitHubAppServerToServerToken},
		{token: "ghs_hbhFI4XWdB6iL1XcxYV8A4pDLlOg9z1eXSQZ", expected: GitHubAppServerToServerToken},
		{token: "ghs_82ejQiujh0JbwMnhm7OBRJvdEngzV73zNP77", expected: GitHubAppServerToServerToken},
	} {
		assert.Equal(t, tc.expected, GetTokenType(tc.token), tc.token)
	}
}
