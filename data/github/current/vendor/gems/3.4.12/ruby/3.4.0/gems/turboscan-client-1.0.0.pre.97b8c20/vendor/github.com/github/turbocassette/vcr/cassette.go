package vcr

import (
	"encoding/base64"
	"io"
	"net/http"
	"reflect"

	"gopkg.in/yaml.v3"
)

// See Cassette format https://relishapp.com/vcr/vcr/v/6-1-0/docs/cassettes/cassette-format
type Body struct {
	Encoding string `yaml:"encoding"`
	String   string `yaml:"string"`
}

type Encoding string

var Base64Encoding Encoding = "base64"

func NewBody(data string, encoding Encoding) *Body {
	if encoding == "base64" {
		return &Body{
			Encoding: "base64",
			String:   base64.StdEncoding.EncodeToString([]byte(data)),
		}
	}
	return &Body{
		Encoding: "UTF-8",
		String:   data,
	}
}

type Status struct {
	Code    int     `yaml:"code"`
	Message *string `yaml:"message"`
}

type Response struct {
	Status      *Status      `yaml:"status"`
	Headers     http.Header  `yaml:"headers"`
	Body        *Body        `yaml:"body"`
	HttpVersion *interface{} `yaml:"http_version"`
}

type Request struct {
	Method  string      `yaml:"method"`
	URI     string      `yaml:"uri"`
	Body    *Body       `yaml:"body"`
	Headers http.Header `yaml:"headers"`
	//Form    url.Values  `yaml:"form,omitempty"`
}

type Interaction struct {
	Request    *Request  `yaml:"request"`
	Response   *Response `yaml:"response"`
	RecordedAt string    `yaml:"recorded_at"`
}

type Cassette struct {
	Interactions []*Interaction `yaml:"http_interactions"`
	RecordedWith string         `yaml:"recorded_with"`
}

func Open(r io.Reader) (*Cassette, error) {
	decoder := yaml.NewDecoder(r)
	decoder.KnownFields(true)

	var tape Cassette
	if err := decoder.Decode(&tape); err != nil {
		return nil, err
	}
	return &tape, nil
}

func (c *Cassette) Encode(w io.Writer) error {
	encoder := yaml.NewEncoder(w)
	encoder.SetIndent(2)
	return encoder.Encode(&c)
}

// normalizeResponse strips out anything from response that may change between runs
// but has no effect on the equality of a response
func normalizeResponse(response *Response) *Response {
	if response == nil {
		return nil
	}

	clone := &Response{}
	*clone = *response

	if response.Headers != nil {
		clone.Headers = response.Headers.Clone()
		clone.Headers.Set("Content-Length", "0")
	}

	return clone
}

func IsResponseModified(before *Response, after *Response) bool {
	return !reflect.DeepEqual(normalizeResponse(before), normalizeResponse(after))
}
