package github

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/google/go-github/v65/github"
	"golang.org/x/net/html"
)

// Enforce that staffToolsServiceImpl implements the StaffToolsService
// interface.
var _ StaffToolsService = &staffToolsServiceImpl{}

// StaffToolsService is an interface which describes the methods of the
// Staff Tools API. These methods ARE NOT implemented in the upstream
// go-github library. We follow their `XService` pattern for consistency.
type StaffToolsService interface {
	UnlockRepository(ctx context.Context, owner string, repo string, reason string) error
}

type staffToolsServiceImpl struct {
	client *github.Client
}

// UnlockRepository unlocks a repository using the Staff Tools API.
// It sends a GET request to the unlock page, parses the HTML to find the
// appropriate form, and submits the form to unlock the repository.
//
// A pre-requisite to calling this function is that the client must be
// logged in.
//
// Returns an error if the request fails or if the repository cannot be unlocked.
func (s *staffToolsServiceImpl) UnlockRepository(ctx context.Context, owner, name, reason string) error {
	unlockURL := &url.URL{Path: fmt.Sprintf("/stafftools/repositories/%s/%s/security", owner, name)}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.client.BaseURL.ResolveReference(unlockURL).String(), http.NoBody)
	if err != nil {
		return fmt.Errorf("error creating HTTP request for the security page: %w", err)
	}

	// Use a special client that does not follow redirects. "Why would you do that?"
	// great question! When you attempt to access the stafftools UI when not logged
	// in, you receive a 302 to the login page which then returns a 200. To ensure
	// that we're both logged in and receive the security page, we disable redirect
	// following.
	//
	// Special note: `Client()` returns a copy of the client. Modifying this returned
	// copy does not change the original.
	httpClient := s.client.Client()
	httpClient.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		return http.ErrUseLastResponse
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("error while requesting security page: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusFound {
		return fmt.Errorf("client not logged in")
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status code from security page: %d", resp.StatusCode)
	}

	// Parse the returned HTML. I could not find a situation in which `nil`
	// is returned. The documentation for `Parse` doesn't make any comments
	// about this, so catch the situation just in case.
	responseHTML, err := html.Parse(resp.Body)
	if err != nil {
		return fmt.Errorf("error while parsing html of unlock page: %w", err)
	}

	if responseHTML == nil {
		return fmt.Errorf("parsed html resulted in a nil object")
	}

	// The `cancel_unlock` action is present if the repository is already
	// unlocked. If this is the case (i.e. the action url is found), return
	// early.
	cancelFormActionURL, _, err := extractFormValues(responseHTML, "cancel_unlock")
	if err != nil {
		return fmt.Errorf("error while parsing unlock page: %w", err)
	}

	if cancelFormActionURL != nil {
		return nil
	}

	// Check the HTML again, this time searching for the `staff_unlock` form. This
	// form contains the information we need to perform an unlock. Specifically,
	// we need the authenticity token from the form. If we can't find the unlock
	// form return an error. If we do, inject our own parameters into the values
	// found in the field.
	unlockFormActionURL, unlockFormValues, err := extractFormValues(responseHTML, "staff_unlock")
	if err != nil {
		return fmt.Errorf("error while parsing unlock page: %w", err)
	}

	if unlockFormActionURL == nil {
		return fmt.Errorf("unable to find unlock form on security page")
	}

	unlockFormValues.Set("reason", reason)

	// POST to perform an unlock. If a non-200 is returned, return an error.
	// We do not use the redirect-less client from before. It is expected that
	// the POST result in a 302, and then a 200.
	unlockFormActionURL = resp.Request.URL.ResolveReference(unlockFormActionURL)
	req, err = http.NewRequestWithContext(ctx, http.MethodPost, unlockFormActionURL.String(), strings.NewReader(unlockFormValues.Encode()))
	if err != nil {
		return fmt.Errorf("error creating http request to perform unlock: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err = s.client.Client().Do(req)
	if err != nil {
		return fmt.Errorf("error posting form for unlock: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("non-200 status code returned from unlock attempt, got: %d", resp.StatusCode)
	}

	return nil
}
