package github

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
	"golang.org/x/net/html"
)

// LoginToWebUI is a function which performs a login through the web form. This
// behavior is required by certain tests in order to have the login cookies present within
// the HTTP client. The username and password provided are the credentials used to
// log in to the UI.
func (c *Client) LoginToWebUI(ctx context.Context, username, password string) error {
	baseURL := &url.URL{
		Host:   c.restClient.BaseURL.Host,
		Scheme: c.restClient.BaseURL.Scheme,
	}
	loginURL := &url.URL{Path: "/login"}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL.ResolveReference(loginURL).String(), http.NoBody)
	if err != nil {
		return fmt.Errorf("error creating http request for the login page: %w", err)
	}

	resp, err := c.restClient.Client().Do(req)
	if err != nil {
		return fmt.Errorf("error while requesting the login page: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("non-200 returned from login page, got: %d", resp.StatusCode)
	}

	// Parse the returned HTML. I could not find a situation in which `nil`
	// is returned. The documentation for `Parse` doesn't make any comments
	// about this, so catch the situation just in case.
	responseHTML, err := html.Parse(resp.Body)
	if err != nil {
		return fmt.Errorf("error while parsing html of unlock page: %w", err)
	}

	if responseHTML == nil {
		return fmt.Errorf("unlock page did not return html")
	}

	formActionURL, formValues, err := extractFormValues(responseHTML, "session")
	if err != nil {
		return fmt.Errorf("error while parsing login page: %w", err)
	}

	formValues.Set("login", username)
	formValues.Set("password", password)
	formActionURL = resp.Request.URL.ResolveReference(formActionURL)

	req, err = http.NewRequestWithContext(ctx, http.MethodPost, formActionURL.String(), strings.NewReader(formValues.Encode()))
	if err != nil {
		return fmt.Errorf("error creating http request to perform login: %w", err)
	}

	// Create a special HTTP client that does not follow redirects.
	// If the login is successful, a 302 is returned. If the login is not
	// successful, a 200 is returned. Note: This client is a copy, and
	// modifying it does not modify the GitHub client's HTTP client.
	httpClient := c.restClient.Client()
	httpClient.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		return http.ErrUseLastResponse
	}

	resp, err = httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("error posting form to login: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusFound {
		if resp.StatusCode == http.StatusOK {
			return fmt.Errorf("invalid login, check credentials and try again")
		}
		return fmt.Errorf("unexpected status code returned after login attempt, got %d", resp.StatusCode)
	}

	return nil
}

// extractFormValues is a function which finds the form within the provided HTML.
// It extracts the form inputs, stores them in a `url.Values`, and returns them along
// with the action URL. A `actionFilter` may be provided to help find the correct form.
// If no `actionFilter` is provided, the first form found will be used. If `actionFilter`
// is provided and no form matches, `nil` will be returned without an error.
func extractFormValues(root *html.Node, actionFilter string) (*url.URL, url.Values, error) {
	if root == nil {
		return nil, url.Values{}, fmt.Errorf("cannot parse nil HTML node")
	}

	var form *goquery.Selection
	values := url.Values{}
	doc := goquery.NewDocumentFromNode(root)

	if actionFilter == "" {
		form = doc.Find("form").First()
	} else {
		doc.Find("form").Each(func(i int, selection *goquery.Selection) {
			action, exists := selection.Attr("action")
			if exists && strings.Contains(action, actionFilter) {
				form = selection
				return
			}
		})
	}
	if form == nil {
		return nil, values, nil
	}

	action, _ := form.Attr("action")

	form.Find("input").Each(func(_ int, s *goquery.Selection) {
		name, _ := s.Attr("name")
		if name == "" {
			return
		}

		value, _ := s.Attr("value")
		values.Add(name, value)
	})

	actionURL, err := url.Parse(action)
	if err != nil {
		return actionURL, values, fmt.Errorf("error parsing form action URL: %w", err)
	}

	return actionURL, values, nil
}
