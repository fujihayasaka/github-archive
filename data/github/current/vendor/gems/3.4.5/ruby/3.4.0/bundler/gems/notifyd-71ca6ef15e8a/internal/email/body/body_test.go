package body

import (
	"encoding/base64"
	"net/mail"
	"net/textproto"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/email/testhelper"
)

// NOTE: This test uses an external fixture file inside of testdata/email*.txt as it otherwise it was
// impossible to make Go respect the format for the email, which includes a carriage return for each
// new line (i.e. CRLF).
//
// Also take into account that if you add a new file it should respect the pattern set on the
// .gitattributes file so that the CRLF is respected on checkout. Who said computers were boring,
// uh?
//
// If you need to modify the fixture file and add new carriage returns it can be done on Vim like
// editors by using CTRL-V CTRL-M
func Test_Compose(t *testing.T) {
	tests := []struct {
		name    string
		fixture string
		body    func(t *testing.T) Body
	}{
		{
			name:    "parts with pre-defined Content-Transfer-Encoding",
			fixture: "email_predefined_transfer_encoding",
			body: func(t *testing.T) Body {
				t.Helper()

				b := New()
				b.AddPart("This is the TEXT part", textproto.MIMEHeader{
					"Content-Type":              {"text/plain; charset=utf-8"},
					"Content-Transfer-Encoding": {"7bit"},
				})
				b.AddPart(`This is the <b style="display: none">HTML</b> part`, textproto.MIMEHeader{
					"Content-Type":              {"text/html; charset=utf-8"},
					"Content-Transfer-Encoding": {"7bit"},
				})
				return b
			},
		},
		{
			name:    "parts with undefined Content-Transfer-Encoding",
			fixture: "email_undefined_transfer_encoding",
			body: func(t *testing.T) Body {
				t.Helper()

				b := New()
				b.AddPart("This is the TEXT part", textproto.MIMEHeader{
					"Content-Type": {"text/plain; charset=utf-8"},
				})
				b.AddPart(`This is the <b style="display: none">HTML</b> part`, textproto.MIMEHeader{
					"Content-Type": {"text/html; charset=utf-8"},
				})
				return b
			},
		},
		{
			name:    "parts already encoded",
			fixture: "email_preencoded_parts",
			body: func(t *testing.T) Body {
				t.Helper()

				b := New()
				b.AddEncodedPart(base64.StdEncoding.EncodeToString([]byte("This is the TEXT part")), textproto.MIMEHeader{
					"Content-Type":              {"text/plain; charset=utf-8"},
					"Content-Transfer-Encoding": {"base64"},
				})
				b.AddEncodedPart(`This is the <b style=3D"display: none">HTML</b> part`, textproto.MIMEHeader{
					"Content-Type":              {"text/html; charset=utf-8"},
					"Content-Transfer-Encoding": {"quoted-printable"},
				})

				return b
			},
		},
		{
			name:    "with a single part",
			fixture: "email_single_part",
			body: func(t *testing.T) Body {
				t.Helper()

				b := New()
				b.AddPart(`This is the <b style="display: none">HTML</b> part`, textproto.MIMEHeader{
					"Content-Type": {"text/html; charset=utf-8"},
				})
				return b
			},
		},
		{
			name:    "with ignored attributes",
			fixture: "email_undefined_transfer_encoding",
			body: func(t *testing.T) Body {
				t.Helper()

				b := New()
				b.AddField("MIME-Version", "Ignore me!")
				b.AddPart("This is the TEXT part", textproto.MIMEHeader{
					"Content-Type": {"text/plain; charset=utf-8"},
				})
				b.AddPart(`This is the <b style="display: none">HTML</b> part`, textproto.MIMEHeader{
					"Content-Type": {"text/html; charset=utf-8"},
				})
				return b
			},
		},
		{
			name:    "with a subject with UTF-8 characters",
			fixture: "email_subject_utf8",
			body: func(t *testing.T) Body {
				t.Helper()

				b := New()
				b.AddField("Subject", "This is a test ケータイ")
				b.AddPart("This is the TEXT part", textproto.MIMEHeader{
					"Content-Type": {"text/plain; charset=utf-8"},
				})
				b.AddPart(`This is the <b style="display: none">HTML</b> part`, textproto.MIMEHeader{
					"Content-Type": {"text/html; charset=utf-8"},
				})
				return b
			},
		},
		{
			name:    "with a from and cc addresses",
			fixture: "email_from_address",
			body: func(t *testing.T) Body {
				t.Helper()

				b := New()
				b.AddAddressList("From", []*mail.Address{{Name: "Jane Doe", Address: "jane.doe@example.org"}})
				b.AddAddressList("Cc", []*mail.Address{
					{
						Name:    "Mention",
						Address: "mention@example.org",
					},
					{
						Name:    "Subscribed",
						Address: "subscribed@example.org",
					},
				})
				b.AddPart("This is the TEXT part", textproto.MIMEHeader{
					"Content-Type": {"text/plain; charset=utf-8"},
				})
				b.AddPart(`This is the <b style="display: none">HTML</b> part`, textproto.MIMEHeader{
					"Content-Type": {"text/html; charset=utf-8"},
				})
				return b
			},
		},
		{
			name:    "with a from address with UTF-8 characters",
			fixture: "email_from_address_utf8",
			body: func(t *testing.T) Body {
				t.Helper()

				b := New()
				b.AddAddressList("From", []*mail.Address{{Name: "Jane ケータイ", Address: "jane.doe@example.org"}})
				b.AddPart("This is the TEXT part", textproto.MIMEHeader{
					"Content-Type": {"text/plain; charset=utf-8"},
				})
				b.AddPart(`This is the <b style="display: none">HTML</b> part`, textproto.MIMEHeader{
					"Content-Type": {"text/html; charset=utf-8"},
				})
				return b
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(ti *testing.T) {
			b := test.body(t)
			body, err := b.Compose()
			require.NoError(ti, err)

			testhelper.IsEqualToFixture(ti, &testhelper.Fixture{Name: test.fixture}, body)
		})
	}
}
