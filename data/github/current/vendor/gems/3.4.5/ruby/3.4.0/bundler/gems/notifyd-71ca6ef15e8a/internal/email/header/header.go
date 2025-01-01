// Package header contains utility functions for email header building, used for processing different layouts.
package header

import (
	"context"
	"fmt"
	gomail "net/mail"
	"net/textproto"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/github/notifyd/internal/email/body"
)

const (
	fromFieldKey                  = "From"
	toFieldKey                    = "To"
	ccFieldKey                    = "Cc"
	reasonFieldKey                = "X-GitHub-Reason"
	recipientFieldKey             = "X-GitHub-Recipient"
	listUnsubscribeFieldKey       = "List-Unsubscribe"
	listUnsubscribePostFieldKey   = "List-Unsubscribe-Post"
	listUnsubscribePostFieldValue = "List-Unsubscribe=One-Click"
	replyToFieldKey               = "Reply-To"
)

type fromData interface {
	GetName() string
	GetEmail() string
}

// A Field knows how to add itself to a mail.Body, depending on the data that it holds
type Field interface {
	Key() string
	Value() string
	AddTo(body.Body)
}

// ListUnsubscribe follows the RFC 8058[1]
// It assumes that the given URL is a POST endpoint that can unsubscribe the emailed resource
// It also adds a valid email address to unsubscribe if present
// [1]: https://datatracker.ietf.org/doc/html/rfc8058
type ListUnsubscribe struct {
	URL     string
	Address string
}

// IsPresent returns true if the list unsubscribe field is present.
func (list ListUnsubscribe) IsPresent() bool {
	return list.URL != "" || list.Address != ""
}

// Values returns the values of the list unsubscribe field.
func (list ListUnsubscribe) Values() []string {
	values := []string{}

	if list.Address != "" {
		values = append(values, fmt.Sprintf("<mailto:%s>", list.Address))
	}

	if list.URL != "" {
		url := list.URL
		values = append(values, fmt.Sprintf("<%s>", url))
	}

	return values
}

// String returns the string representation of the list unsubscribe field.
func (list ListUnsubscribe) String() string {
	return strings.Join(list.Values(), ", ")
}

// Key returns the key of the list unsubscribe field.
func (list ListUnsubscribe) Key() string {
	return listUnsubscribeFieldKey
}

// Value returns the value of the list unsubscribe field.
func (list ListUnsubscribe) Value() string {
	return list.String()
}

// AddTo adds the list unsubscribe field to the given body.
func (list ListUnsubscribe) AddTo(bdy body.Body) {
	bdy.AddRawField(listUnsubscribeFieldKey, list.String())
	bdy.AddRawField(listUnsubscribePostFieldKey, listUnsubscribePostFieldValue)
}

// EmptyField represents an empty field.
type EmptyField struct{}

// Key returns the key of the empty field.
func (field *EmptyField) Key() string {
	return ""
}

// Value returns the value of the empty field.
func (field *EmptyField) Value() string {
	return ""
}

// AddTo adds the empty field to the given body.
func (field *EmptyField) AddTo(bdy body.Body) {
	// NO-OP
}

// NewEmptyField creates a new empty field.
func NewEmptyField() *EmptyField {
	return &EmptyField{}
}

// RawField represents a raw field.
type RawField struct {
	key   string
	value string
}

// Key returns the key of the raw field.
func (field *RawField) Key() string {
	return field.key
}

// Value returns the value of the raw field.
func (field *RawField) Value() string {
	return field.value
}

// AddTo adds the raw field to the given body.
func (field *RawField) AddTo(bdy body.Body) {
	bdy.AddRawField(field.key, field.value)
}

// NewRawField creates a new raw field.
func NewRawField(name, value string) *RawField {
	return &RawField{key: textproto.CanonicalMIMEHeaderKey(name), value: value}
}

// TextField represents a text field.
type TextField struct {
	key   string
	value string
}

// Key returns the key of the text field.
func (field *TextField) Key() string {
	return field.key
}

// Value returns the value of the text field.
func (field *TextField) Value() string {
	return field.value
}

// AddTo adds the text field to the given body.
func (field *TextField) AddTo(bdy body.Body) {
	bdy.AddField(field.key, field.value)
}

// NewTextField creates a new text field.
func NewTextField(name, value string) *TextField {
	return &TextField{key: textproto.CanonicalMIMEHeaderKey(name), value: value}
}

// AddressListField represents an email address list field.
type AddressListField struct {
	key         string
	addressList []*gomail.Address
}

// Key returns the key of the address list field.
func (field *AddressListField) Key() string {
	return field.key
}

// AddTo adds the address list field to the given body.
func (field *AddressListField) AddTo(bdy body.Body) {
	if len(field.addressList) > 0 {
		bdy.AddAddressList(field.key, field.addressList)
	}
}

// Value returns the value of the address list field.
func (field *AddressListField) Value() string {
	addresses := make([]string, len(field.addressList))
	for idx, address := range field.addressList {
		addresses[idx] = address.Address
	}

	return strings.Join(addresses, ", ")
}

// NewAddressListField creates a new address list field.
func NewAddressListField(name string, addressList []*gomail.Address) *AddressListField {
	return &AddressListField{key: textproto.CanonicalMIMEHeaderKey(name), addressList: addressList}
}

// AddressField represents an email address field.
type AddressField struct {
	key     string
	address *gomail.Address
}

// Key returns the key of the address field.
func (field *AddressField) Key() string {
	return field.key
}

// AddTo adds the address field to the given body.
func (field *AddressField) AddTo(bdy body.Body) {
	bdy.AddAddress(field.key, field.address)
}

// Value returns the value of the address field.
func (field *AddressField) Value() string {
	return field.address.Address
}

// NewAddressField creates a new address field.
func NewAddressField(name string, address *gomail.Address) *AddressField {
	return &AddressField{key: textproto.CanonicalMIMEHeaderKey(name), address: address}
}

// Header represents the email headers.
type Header struct {
	Fields []Field
}

// Has returns true if the header has a field with the given key.
func (header *Header) Has(key string) bool {
	canonical := textproto.CanonicalMIMEHeaderKey(key)

	for _, field := range header.Fields {
		if field.Key() == canonical {
			return true
		}
	}

	return false
}

// Get returns the value of the header with the given key.
func (header *Header) Get(key string) string {
	canonical := textproto.CanonicalMIMEHeaderKey(key)

	for _, field := range header.Fields {
		if field.Key() == canonical {
			return field.Value()
		}
	}

	return ""
}

// BuildCC builds the CC field.
func BuildCC(reasons []string, senderDomain string) Field {
	cc := make([]*gomail.Address, len(reasons))
	for idx, reason := range reasons {
		cc[idx] = buildReasonCC(reason, senderDomain)
	}

	return NewAddressListField(ccFieldKey, cc)
}

// buildReasonCC builds a CC field for a given reason.
func buildReasonCC(reason, senderDomain string) *gomail.Address {
	nameTitle := ""

	reasonName := reason
	reasonEmailPrefix := reason
	if reason == "list_subscription" {
		reasonName = "subscribed"
		reasonEmailPrefix = "subscribed"
	} else if reason == "thread_type_subscription" {
		reasonName = "subscribed"
		reasonEmailPrefix = "subscribed"
	}

	if reasonName != "" {
		reasonName = strings.ReplaceAll(reasonName, "_", " ")
		reasonName = strings.ReplaceAll(reasonName, "-", " ")
		nameTitle = strings.ToUpper(reasonName[:1]) + reasonName[1:]
	}
	address := fmt.Sprintf("%s@noreply.%s", reasonEmailPrefix, senderDomain)

	return &gomail.Address{Name: nameTitle, Address: address}
}

// BuildTo builds the To field.
func BuildTo(ctx context.Context, logger log.Logger, str string) Field {
	if str == "" {
		return NewEmptyField()
	}

	address, err := gomail.ParseAddress(str)
	if err != nil {
		logger.WithFields(kvp.String("code.function", "header.BuildTo")).
			WithError(err).
			Info("warning: error trying to parse an address for the field To, falling back to the original address provided")

		return NewRawField(toFieldKey, str)
	}

	return NewAddressField(toFieldKey, address)
}

// BuildHeader builds the headers.
func BuildHeader(headers map[string]string, reason, recipientLogin string, listUnsubscribe ListUnsubscribe, replyTo string) *Header {
	if headers == nil {
		headers = make(map[string]string)
	}

	fields := make([]Field, 0)

	for key, value := range headers {
		fields = append(fields, NewRawField(key, value))
	}

	if reason != "" {
		fields = append(fields, NewTextField(reasonFieldKey, reason))
	}

	if recipientLogin != "" {
		fields = append(fields, NewTextField(recipientFieldKey, recipientLogin))
	}

	if listUnsubscribe.IsPresent() {
		fields = append(fields, listUnsubscribe)
	}

	if replyTo != "" {
		fields = append(fields, NewAddressField(replyToFieldKey, &gomail.Address{Address: replyTo}))
	}

	return &Header{Fields: fields}
}

// BuildReason builds the reason field.
func BuildReason(reasons []string) string {
	return strings.Join(reasons, "; ")
}

// BuildFrom builds the From field.
func BuildFrom(ctx context.Context, from fromData, defaultEmail string) Field {
	address := from.GetEmail()
	if address == "" {
		address = defaultEmail
	}

	name := from.GetName()
	if name == "" {
		name = "GitHub"
	}

	return NewAddressField(fromFieldKey, &gomail.Address{Name: name, Address: address})
}

var ignoredFields = []string{"from", "to", "subject", "cc"}

// IsIgnoredField returns true for headers fields in the email that should be ignored as are set by notifyd.
func IsIgnoredField(field string) bool {
	field = strings.ToLower(field)
	for _, forbiddenField := range ignoredFields {
		if field == forbiddenField {
			return true
		}
	}

	return false
}
