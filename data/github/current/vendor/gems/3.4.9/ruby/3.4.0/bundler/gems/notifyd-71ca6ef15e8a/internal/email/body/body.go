/*
Package body manages the composition of a Mail body

A Mail is composed by two main sections:
  - Header: a collection of fields in the form "Key: Value"
  - Content: (also called just body), the content of the mail itself

The content of a Mail can have multiple parts, different representations so clients can chose the best one.
For example, is common o have a part for `text/plain` content and another one for `text/html`.

The composition of a Mail is defined in the [RFC 5322].
Some of the most important parts of this specification are:

  - All content (header fields and content) must be in US-ASCII. Any character outside this charset must be encoded
  - There is a size limit per line, inluding headers. The max is 998 characters and the suggested limit is 78 characters

The process of breaking up a long line in a header field so it fits into the characters limit is called folding.

This package tries to take care of all of the above by encoding and folding header fields whenever possible and by encoding
`text/*` parts using `quoted-printable` encoding as described in [RFC 2045] to ensure no content is lost on the wire
and that we play nice with Mail clients.

In order to ensure header fields are properly formatted, we need to differentiate between what kind of fields we have

  - Date field
  - Text fields: like `Subject`
  - Address List fields: Anything with a valid email address.
    Addreses can be represented with a simple address like "<jane@doe.io>". They can also be composed of a name and the address
    like `"Jane Doe" <jane@doe.io>`. In the last case the name needs to be encoded in case it has UTF-8 characters
    (outside the US-ASCII charset).

There is also a posibility to add preformatted fields, called raw fields, but this is discouraged.

To handle all the encodings this packages uses the [go-message] package to build the Mail header
and mime/multipart to build the Mail body.

[RFC 5322]: https://www.rfc-editor.org/rfc/rfc5322
[RFC 2045]: https://www.rfc-editor.org/rfc/rfc2045#page-19
[go-message]: https://github.com/emersion/go-message
*/
package body

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"mime/multipart"
	"mime/quotedprintable"
	gomail "net/mail"
	"net/textproto"
	"sort"
	"strings"
	"time"

	"github.com/emersion/go-message/mail"
	msgtextproto "github.com/emersion/go-message/textproto"
	"github.com/emersion/go-textwrapper"

	"github.com/github/notifyd/internal/pkg/errors"
)

type nopCloser struct {
	io.Writer
}

func (nopCloser) Close() error {
	return nil
}

type part struct {
	body    string
	fields  textproto.MIMEHeader
	encoded bool
}

type field struct {
	name string
	body string
}

type addressField struct {
	name      string
	addresses []*gomail.Address
}

// Body represents the whole data of an mail. It includes both the header and the content. The
// header is built of multiple fields, while the content is usually composed of different parts,
// html and text.
type Body interface {
	AddDate(date time.Time)
	AddField(key string, value string)
	AddRawField(key string, value string)
	AddAddress(key string, address *gomail.Address)
	AddAddressList(key string, list []*gomail.Address)
	AddPart(body string, header textproto.MIMEHeader)
	AddEncodedPart(body string, header textproto.MIMEHeader)
	Compose() ([]byte, error)
}

type mailbody struct {
	fields    []field
	addresses []addressField
	rawFields []field
	date      time.Time
	parts     []part
}

// New creates a new Body
func New() Body {
	return &mailbody{}
}

// Adds a Date field to the mail header, for example:
//
// b := New()
// b.AddDate(time.Now())
//
// Will add a field like:
//
// Date: Mon, 2 Jan 06 15:04:05 MST\r\n
func (b *mailbody) AddDate(date time.Time) {
	b.date = date
}

// Adds a field to the mail header, for example:
//
// b := New()
// b.AddField("Subject", "Something has happened!")
//
// Will add a field like:
//
// Subject: Something has happened\r\n
//
// If a field has non US-ASCII character these will be encoded
func (b *mailbody) AddField(name, body string) {
	b.fields = append(b.fields, field{name: name, body: body})
}

// Adds a new Address List field to the mail header, for example:
//
// b := New()
// b.AddAddressList("Cc", []*mail.Address{{Name: "Jane Doe", Address: "jane@doe.io"}})
//
// Will add a field like:
//
// Cc: "Jane Doe" <jane@doe.io>\r\n
//
// An Address List can have one or more addresses in it
// If a field has non US-ASCII character these will be encoded
func (b *mailbody) AddAddressList(name string, addresses []*gomail.Address) {
	b.addresses = append(b.addresses, addressField{name: name, addresses: addresses})
}

// Adds a new Address List field with one Address to the mail header, for example:
//
// b := New()
// b.AddAddress("To", *mail.Address{Name: "Jane Doe", Address: "jane@doe.io"})
//
// Will add a field like:
//
// To: "Jane Doe" <jane@doe.io>\r\n
//
// If a field has non US-ASCII character these will be encoded
func (b *mailbody) AddAddress(name string, address *gomail.Address) {
	b.AddAddressList(name, []*gomail.Address{address})
}

// Adds a field to the mail header without trying to encode it, for example:
//
// b := New()
// b.AddRawField("Date", "Thu, 19 May 2022 00:50:06 -0700")
//
// Will add a field like:
//
// Date: Thu, 19 May 2022 00:50:06 -0700\r\n
//
// This assumes that the field has been properly encoded beforehand
func (b *mailbody) AddRawField(name, body string) {
	b.rawFields = append(b.rawFields, field{name: name, body: body})
}

// Adds content as a new multipart element. It handles boundaries and setting the needed layout on
// the mail on its own.
// A part can declare how it can be encoded with Content-Transfer-Encoding, but it MUST NOT be
// encoded already since that will be done during the body composition
// To add pre-encoded parts see Body.AddEncodedPart()
//
// Example:
//
//	b := New()
//	b.AddPart(`This is the <b style="display: none">HTML</b> part`, textproto.MIMEHeader{
//		"Content-Type":              {"text/html; charset=utf-8"},
//		"Content-Transfer-Encoding": {"quoted-printable"},
//	})
func (b *mailbody) AddPart(body string, fields textproto.MIMEHeader) {
	b.parts = append(b.parts, part{body: body, fields: fields, encoded: false})
}

// Adds pre-encoded content as a new multipart element.
// It ensures that it will not be double encoded later when the mail is composed
// An encoded part must declare the encoding with the field Content-Transfer-Encoding
// and it's content type with Content-Type
//
// Example:
//
//	b := New()
//	b.AddEncodedPart(`This is the <b style=3D"display: none">HTML</b> part`, textproto.MIMEHeader{
//		"Content-Type":              {"text/html; charset=utf-8"},
//		"Content-Transfer-Encoding": {"quoted-printable"},
//	})
func (b *mailbody) AddEncodedPart(body string, fields textproto.MIMEHeader) {
	b.parts = append(b.parts, part{body: body, fields: fields, encoded: true})
}

// Compose returns the final byte array containing the whole body of the mail as it can be
// delivered via SMTP.
func (b *mailbody) Compose() ([]byte, error) {
	data := &bytes.Buffer{}
	var header mail.Header

	header.Set("MIME-Version", "1.0")

	if !b.date.IsZero() {
		header.SetDate(b.date)
	}

	for _, field := range b.addresses {
		if isIgnoredField(field.name) {
			continue
		}

		header.SetAddressList(field.name, field.addresses)
	}

	for _, field := range b.fields {
		if isIgnoredField(field.name) {
			continue
		}

		header.SetText(field.name, field.body)
	}

	for _, field := range b.rawFields {
		if isIgnoredField(field.name) {
			continue
		}

		// We don't encode Raw fields, we assume that they are in the right format for the moment
		header.Set(field.name, field.body)
	}

	if len(b.parts) == 1 {
		if err := b.addSinglePart(data, &header); err != nil {
			return nil, errors.Wrap(err, "mail: error creating single body part")
		}
	} else {
		if err := b.addMultiParts(data, &header); err != nil {
			return nil, errors.Wrap(err, "mail: error creating multi body parts")
		}
	}

	return data.Bytes(), nil
}

func (b *mailbody) addSinglePart(data io.ReadWriter, header *mail.Header) error {
	if len(b.parts) == 0 {
		return errors.New("body: trying to build a single part body with no parts")
	}

	part := b.parts[0]
	buildHeaderForPart(header, &part)

	if err := msgtextproto.WriteHeader(data, header.Header.Header); err != nil {
		return err
	}

	var buf io.Reader
	if !part.encoded {
		var err error
		buf, err = encode(header.Get("Content-Transfer-Encoding"), strings.NewReader(part.body))
		if err != nil {
			return err
		}
	} else {
		buf = strings.NewReader(part.body)
	}

	if _, err := io.Copy(data, buf); err != nil {
		return err
	}

	return nil
}

func (b *mailbody) addMultiParts(data io.ReadWriter, header *mail.Header) error {
	boundary, err := b.generateBoundary(data)
	if err != nil {
		return err
	}
	header.Set("Content-Type", fmt.Sprintf("multipart/alternative; boundary=%q; charset=UTF-8", boundary))

	if err := msgtextproto.WriteHeader(data, header.Header.Header); err != nil {
		return err
	}

	multiparts := multipart.NewWriter(data)
	defer multiparts.Close()

	if err := multiparts.SetBoundary(boundary); err != nil {
		return errors.Wrap(err, "overwriting mime boundary")
	}

	for _, part := range b.parts {
		fields := part.fields
		if val := fields.Get("Content-Transfer-Encoding"); val == "" {
			if contentType := fields.Get("Content-Type"); contentType != "" {
				if strings.HasPrefix(contentType, "text/") {
					fields.Set("Content-Transfer-Encoding", "quoted-printable")
				} else {
					fields.Set("Content-Transfer-Encoding", "base64")
				}
			}
		}

		// NOTE: The part headers are not going to be encoded or split in lines
		//   but since they are usually only Content-* headers, we should be fine
		partWriter, err := multiparts.CreatePart(fields)
		if err != nil {
			return err
		}

		var buf io.Reader
		if !part.encoded {
			buf, err = encode(fields.Get("Content-Transfer-Encoding"), strings.NewReader(part.body))
			if err != nil {
				return err
			}
		} else {
			buf = strings.NewReader(part.body)
		}

		if _, err := io.Copy(partWriter, buf); err != nil {
			return err
		}
	}

	return nil
}

func buildHeaderForPart(header *mail.Header, prt *part) {
	// When adding the header keys, we want to make the order constant
	// that's why the keys are ordered
	keys := make([]string, 0, len(prt.fields))
	for pk := range prt.fields {
		keys = append(keys, pk)
	}
	sort.Strings(keys)
	for _, key := range keys {
		header.Set(key, prt.fields.Get(key))
	}

	if !header.Has("Content-Transfer-Encoding") {
		t, _, _ := header.ContentType()
		if strings.HasPrefix(t, "text/") {
			header.Set("Content-Transfer-Encoding", "quoted-printable")
		} else {
			header.Set("Content-Transfer-Encoding", "base64")
		}
	}
}

// generateBoundary uses the header built up until now to generate the boundary. This allows us to
// have a boundary that is partially random but that can still be tested against.
func (b *mailbody) generateBoundary(data io.Reader) (string, error) {
	hasheable := &bytes.Buffer{}
	_, err := io.Copy(hasheable, data)
	if err != nil {
		return "", err
	}

	for _, part := range b.parts {
		if _, err := fmt.Fprint(hasheable, part.body); err != nil {
			return "", err
		}
	}

	hash := sha256.New()
	if _, err := hash.Write(hasheable.Bytes()); err != nil {
		return "", err
	}
	sum := hash.Sum(nil)

	// We use a similar mechanism to the one in ruby's mail gem:
	// https://github.com/mikel/mail/blob/641060598f8f4be14d79bad8d703e9f2967e1cdb/lib/mail/fields/content_type_field.rb#L20
	return fmt.Sprintf("part_%x", sum), nil
}

func encode(enc string, data io.Reader) (io.Reader, error) {
	buf := &bytes.Buffer{}
	encoder, err := encodingWriter(enc, buf)
	if err != nil {
		return nil, err
	}
	defer encoder.Close()

	if _, err := io.Copy(encoder, data); err != nil {
		return nil, err
	}

	return buf, nil
}

// This has been extracted from the emersion/go-message package.
// go-message does a great job encoding the body of a Mail based on its Content-Transfer-Encoding
// It does so by encoding and splitting long lines. Sadly it doesn't expose how it does it,
// but the logic is small enough for us to take it and adapt it.
func encodingWriter(enc string, w io.Writer) (io.WriteCloser, error) {
	var writer io.WriteCloser
	switch strings.ToLower(enc) {
	case "quoted-printable":
		writer = quotedprintable.NewWriter(w)
	case "base64":
		// By using textwrapper we prevent the base64 blob to be one single long line
		writer = base64.NewEncoder(base64.StdEncoding, textwrapper.NewRFC822(w))
	case "7bit", "8bit":
		// Normal text has to be wrapped as well
		writer = nopCloser{textwrapper.New(w, "\r\n", 1000)}
	case "binary", "":
		writer = nopCloser{w}
	default:
		return nil, errors.Newf("unhandled encoding %q", enc)
	}
	return writer, nil
}

// ignoredFields Are fields that we don't allow integrators to override.
var ignoredFields = []string{"MIME-Version", "Content-Type", "Content-Transfer-Encoding"}

func isIgnoredField(field string) bool {
	for _, forbiddenField := range ignoredFields {
		if field == forbiddenField {
			return true
		}
	}

	return false
}
