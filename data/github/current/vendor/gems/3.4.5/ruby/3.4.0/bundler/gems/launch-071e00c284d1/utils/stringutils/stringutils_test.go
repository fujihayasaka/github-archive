package stringutils

import (
	"bytes"
	"io"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHTTPRequestToString(t *testing.T) {
	body := io.NopCloser(bytes.NewReader([]byte("{ \"steps\" : [] }")))
	request, err := http.NewRequest("GET", "https://github.com", body)
	request.Header.Add("Authorization", "auth")
	request.Header.Add("Request-Id", "1234")

	assert.Nil(t, err)
	assert.NotNil(t, request)

	str, err := HTTPRequestToString(request)
	assert.Nil(t, err)

	// Ensure the Authorization header is not included
	expected := "GET / HTTP/1.1\r\n" +
		"Host: github.com\r\n" +
		"Request-Id: 1234\r\n\r\n" +
		"{ \"steps\" : [] }"

	assert.Equal(t, expected, str)

	// Ensure the original request is not modified
	assert.Equal(t, "auth", request.Header.Get("Authorization"))
	b, err := io.ReadAll(request.Body)
	assert.Nil(t, err)
	assert.Equal(t, "{ \"steps\" : [] }", string(b))
}

func TestHash(t *testing.T) {
	assert.Equal(t, uint32(0x811C9DC5), Hash(""))
	assert.Equal(t, uint32(0x250C8F7F), Hash(" "))
	assert.Equal(t, uint32(0xE40C292C), Hash("a"))
	assert.Equal(t, uint32(0xE70C2DE5), Hash("b"))
	assert.Equal(t, uint32(0x1A47E90B), Hash("abc"))
	assert.Equal(t, uint32(0x452C18F6), Hash("Octocat"))
}
