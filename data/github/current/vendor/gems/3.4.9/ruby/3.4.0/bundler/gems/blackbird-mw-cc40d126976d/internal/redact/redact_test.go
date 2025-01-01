package redact

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_Redact(t *testing.T) {
	var tests = []struct {
		in  string
		out string
	}{
		{
			in:  "token ghp_aBcdeFghIjklMnoPqRSTUvwXYZ1234567890",
			out: "token [REDACTED]",
		},
		{
			// github token hidden in another string
			in:  "token ghp_aBcdeFghIjklMnoPqRSTUvwXYZ1234567890ohnothisisnotgood",
			out: "token [REDACTED]",
		},
		{
			in:  "this is fine",
			out: "this is fine",
		},
		{
			in:  "posting slack message to: https://hooks.slack.com/services/T1BAAA111/B0111AAA111/MMMAAA333CCC222bbbAAA111",
			out: "posting slack message to: [REDACTED]",
		},
		{
			in:  "using rubygems token: rubygems_0123456789abcdef0123456789abcdef0123456789abcdef",
			out: "using rubygems token: [REDACTED]", // See https://github.com/github/redacting-logger/issues/65
		},
		{
			in:  "logging into vault with token: s.FakeToken1234567890123456",
			out: "logging into vault with token: [REDACTED]",
		},
		{
			in:  "token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
			out: "token [REDACTED]",
		},
		{
			// redaction for legacy GitHub PATs also redacts Git OIDs
			in:  `SHA("5187566b9e2a6400..a30eacd73c54c800":),NOT(OR(SHA("9f994f3e33b69e656232516cfebeef5b3fa01597":)))`,
			out: `SHA("5187566b9e2a6400..a30eacd73c54c800":),NOT(OR(SHA("[REDACTED]":)))`,
		},
	}

	for _, test := range tests {
		t.Run(fmt.Sprintf("redact %s", test.in), func(t *testing.T) {
			require.Equal(t, test.out, Redact(test.in))
		})
	}
}
