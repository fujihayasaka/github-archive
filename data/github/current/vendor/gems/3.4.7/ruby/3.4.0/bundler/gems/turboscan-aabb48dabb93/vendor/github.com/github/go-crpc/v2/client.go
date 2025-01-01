package crpc

import (
	"bytes"
	"crypto/rsa"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"math/rand"
	"net/http"
	"time"
)

// Client is a chat rpc client
type Client struct {
	httpClient *http.Client
	key        *rsa.PrivateKey
	options    ClientOptions
	url        string
	rand       *rand.Rand
}

// ClientOptions is all the configuration available
type ClientOptions struct {
	AuthToken      string
	RequestTimeout time.Duration
}

const nonceLength = 20
const letterBytes = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

// NewClient creates a new client for url using certFile as the private key.
func NewClient(url, certFile string) (*Client, error) {
	privKey, err := parsePrivKey(certFile)
	if err != nil {
		return nil, err
	}

	return &Client{
		url: url,
		key: privKey,
	}, nil
}

// NewClientWithKey creates a new client for url using the given private key.
func NewClientWithKey(url string, key *rsa.PrivateKey) *Client {
	return &Client{
		key: key,
		url: url,
	}
}

// WithOptions sets the internal options to the given parameter
func (c *Client) WithOptions(o ClientOptions) *Client {
	c.options = o
	if o.RequestTimeout != 0 {
		if c.httpClient == nil {
			c.httpClient = &http.Client{}
		}
		c.httpClient.Timeout = o.RequestTimeout
	}
	return c
}

// GetOptions returns the current set of options
func (c *Client) GetOptions() ClientOptions {
	return c.options
}

// List retrieves the supported methods from the server.
func (c *Client) List() (*ListResponse, error) {
	req, err := http.NewRequest("GET", c.url, nil)
	if err != nil {
		return nil, err
	}

	sig, err := c.requestSignature(req, "")
	if err != nil {
		return nil, err
	}
	req.Header.Set("Chatops-Signature", sig.HeaderValue())

	httpClient := c.httpClient
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	res, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	var cres ListResponse
	if err := json.NewDecoder(res.Body).Decode(&cres); err != nil {
		return nil, err
	}
	return &cres, nil
}

// Deprecated - use Command instead
func (c *Client) Run(method, user, room string, params map[string]string) (*CommandResponse, *http.Response, error) {
	return c.Command(method, user, room, "", params)
}

// Command is the new Run, it defines a new parameter named "rawCommand" which is
// a new field specified by ChatOps RPC (CRPC). Instead of breaking the API contract of Run,
// we are adding a new method to the client.
func (c *Client) Command(method, user, room, rawCommand string, params map[string]string) (*CommandResponse, *http.Response, error) {
	creq := &CommandRequest{
		Method:     method,
		User:       user,
		RoomID:     room,
		Params:     params,
		RawCommand: rawCommand,
	}

	// url has the method name appended to the path
	url := fmt.Sprintf("%s/%s", c.url, method)

	by, err := json.Marshal(creq)
	if err != nil {
		return nil, nil, err
	}

	req, err := http.NewRequest("POST", url, bytes.NewReader(by))
	if err != nil {
		return nil, nil, err
	}

	// generate random characters for the nonce
	nonce := c.generateNonce(nonceLength)
	req.Header.Set("Chatops-Nonce", nonce)
	req.Header.Set("Chatops-Timestamp", time.Now().Format(time.RFC3339))
	sig, err := c.requestSignature(req, string(by))
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Chatops-Signature", sig.HeaderValue())

	// Content-type is necessary to make sure the controller parses our request
	// body properly
	req.Header.Set("Content-type", "application/json")
	req.Header.Set("Accept", "application/json")

	// Authorization can be used on chatops rpc servers in addition to message signing
	if c.options.AuthToken != "" {
		req.SetBasicAuth("x", c.options.AuthToken)
	}

	httpClient := c.httpClient
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	res, err := httpClient.Do(req)
	if err != nil {
		return nil, res, err
	}
	defer res.Body.Close()
	body, err := ioutil.ReadAll(res.Body)
	if err != nil {
		return nil, res, err
	}

	var cres CommandResponse

	if err := json.Unmarshal(body, &cres); err != nil {
		return nil, res, err
	}

	return &cres, res, nil
}

func parsePrivKey(certFile string) (*rsa.PrivateKey, error) {
	privBy, err := ioutil.ReadFile(certFile)
	if err != nil {
		return nil, err
	}

	privKey, err := ReadPEMPrivateKey(privBy)
	if err != nil {
		return nil, err
	}

	return privKey, nil
}

func (c *Client) requestSignature(req *http.Request, payload string) (*Signature, error) {
	sigBy, err := Sign(c.key, URLHeaderSignatureInput(req.URL, req.Header, payload))
	if err != nil {
		return nil, err
	}
	return &Signature{KeyID: "cprc-client", Signature: sigBy}, nil
}

func (c *Client) generateNonce(size int) string {
	if c.rand == nil {
		c.rand = rand.New(rand.NewSource(time.Now().UnixNano()))
	}

	nonce := make([]byte, size)
	for i := range nonce {
		nonce[i] = letterBytes[c.rand.Intn(len(letterBytes))]
	}
	return string(nonce)
}
