package main

import (
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"math"
	"net/http"
	"os"
	"strings"
	"time"
)

type CatalogLeaf struct {
	ID              string    `json:"@id"`
	Type            string    `json:"@type"`
	CommitTimeStamp time.Time `json:"commitTimeStamp"`
	NugetID         string    `json:"nuget:id"`
	NugetVersion    string    `json:"nuget:version"`
	CommitID        string    `json:"commitId"`
	Error           error
}

type CatalogPage struct {
	ID              string          `json:"@id"`
	Type            json.RawMessage `json:"@type"` // can be a plain string or an array of strings
	CommitID        string          `json:"commitId"`
	CommitTimeStamp time.Time       `json:"commitTimeStamp"`
	Count           int             `json:"count"`
	Items           []CatalogLeaf   `json:"items"`
	Error           error
}

func main() {
	if len(os.Args[1:]) != 1 {
		panic("Please invoke this command with the page URL.")
	}

	url := os.Args[1]

	ch := make(chan string)
	go downloadPage(url, os.Stderr, withRetries(http.Get, 6), ch)
	os.Stdout.WriteString(<-ch)
}

func downloadPage(pageURL string, errorWriter io.Writer, getFunc func(string) (*http.Response, error), ch chan<- string) {
	page := CatalogPage{}
	resp, err := getFunc(pageURL)
	if err != nil {
		io.WriteString(errorWriter, fmt.Sprintf("{\"error\": \"%v\", \"url\": \"%s\"}", err.Error(), pageURL))
		os.Exit(1)
	}

	dec := json.NewDecoder(resp.Body)
	if err := dec.Decode(&page); err != nil {
		io.WriteString(errorWriter, fmt.Sprintf("{\"error\": \"%v\", \"url\": \"%s\"}", err.Error(), pageURL))
		os.Exit(1)
	}

	pkg := make(chan string)

	for _, leaf := range page.Items {
		go downloadLeaf(leaf.ID, errorWriter, getFunc, pkg)
	}

	var pageJson strings.Builder
	pageJson.WriteString("{ \"Items\": [")
	for index := range page.Items {
		pageJson.WriteString(<-pkg)
		if index < (len(page.Items) - 1) {
			pageJson.WriteString(",")
		}
	}
	pageJson.WriteString("] }")

	ch <- pageJson.String()
}

func downloadLeaf(leafURL string, errorWriter io.Writer, getFunc func(string) (*http.Response, error), ch chan<- string) {
	resp, err := getFunc(leafURL)
	if err != nil {
		io.WriteString(errorWriter, fmt.Sprintf("{\"error\": \"%v\", \"url\": \"%s\"}", err.Error(), leafURL))
		os.Exit(1)
	}

	defer resp.Body.Close()
	body, _ := ioutil.ReadAll(resp.Body)

	ch <- string(body)
}

// Wrap a func(string) (*http.Response, error) with up to maxRetries retries
func withRetries(getFunc func(string) (*http.Response, error), maxRetries int) func(string) (*http.Response, error) {
	return func(url string) (*http.Response, error) {
		retries := 0
		var resp *http.Response
		var err error
		for retries < maxRetries {
			resp, err = getFunc(url)
			if err != nil {
				// If we get an error bail out immediatly
				return resp, err
			} else if resp.StatusCode != 200 {
				// If we get a non 200 status, keep retrying
				wait := time.Duration(math.Pow(2, float64(retries))) * time.Second
				time.Sleep(wait)
				retries += 1
			} else {
				// We have a valid response
				return resp, err
			}
		}
		// We exhausted our max retries. Return the last known response and error
		return resp, err
	}
}
