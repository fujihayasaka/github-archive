package macos_promotion_provider

import (
	"fmt"
	"net/http"
	"time"

	"github.com/github/hosted-compute-core/asymmjwt"
	"github.com/github/maccloud-go-core/maccloud/generated/mcp"
	"github.com/google/uuid"
)

type MCPInstance struct {
	// InstanceURL is the URL of the MCP instance.
	InstanceURL string
	// Client is the client for the MCP instance.
	Client mcp.Api
}

func NewMacInstances(cfg *Config, jwtConfig *asymmjwt.Config) ([]*MCPInstance, error) {
	httpClient := &http.Client{
		Transport: &CustomTransport{
			Transport: http.DefaultTransport,
			Config:    cfg,
			JWTConfig: jwtConfig,
		},
		Timeout: 30 * time.Second,
	}

	mcpAddrs := cfg.GetMCPAddrs()
	if len(mcpAddrs) == 0 {
		return nil, fmt.Errorf("no MCP instances configured")
	}

	var mcpInstances []*MCPInstance
	for _, mcpInstanceURL := range mcpAddrs {
		mcpInstanceClient := mcp.NewApiProtobufClient(mcpInstanceURL, httpClient)
		mcpInstances = append(mcpInstances, &MCPInstance{
			InstanceURL: mcpInstanceURL,
			Client:      mcpInstanceClient,
		})
	}

	return mcpInstances, nil
}

// createToken generates a new JWT for use by the client.
func createToken(cfg *Config, jwtConfig *asymmjwt.Config) (string, error) {
	now := time.Now().UTC()
	token, err := asymmjwt.GenerateJWT(
		jwtConfig.PrivateKey,
		asymmjwt.WithIssuer(cfg.MCPIssuer),
		asymmjwt.WithSubject("MCP Server"),
		asymmjwt.WithExpiration(now.Add(15*time.Minute)),
		asymmjwt.WithNotBefore(now),
		asymmjwt.WithIssuedAt(now),
		asymmjwt.With("jti", uuid.New().String()),
	)
	if err != nil {
		return "", err
	}

	return token, nil
}

// CustomTransport is a custom implementation of http.RoundTripper that adds a header to each request.
type CustomTransport struct {
	Transport   http.RoundTripper
	Config      *Config
	JWTConfig   *asymmjwt.Config
	Token       string
	TokenExpiry time.Time
}

func (c *CustomTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	now := time.Now().UTC()
	if c.Token == "" || now.Add(1*time.Minute).After(c.TokenExpiry) {
		token, err := createToken(c.Config, c.JWTConfig)
		if err != nil {
			return nil, err
		}
		c.Token = token
		c.TokenExpiry = now.Add(15 * time.Minute)
	}
	req.Header.Add("Authorization", "Bearer "+c.Token)
	return c.Transport.RoundTrip(req)
}
