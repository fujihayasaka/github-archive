package main

import (
	"io/ioutil"
	"net/http"
	"os"
	"strings"
	"testing"
)

func MockGet() func(string) (*http.Response, error) {
	return func(url string) (*http.Response, error) {
		respBody := "{\"items\": []}"

		if url == "https://nuget.org/page_no_items" {
			respBody = "{\"items\": []}"
		}

		if url == "https://nuget.org/page_has_items" {
			respBody = "{\"items\": [{\"@id\": \"https://nuget.org/leaf_downloadUrl\"}]}"
		}

		if url == "https://nuget.org/leaf_downloadUrl" {
			respBody = "{ \"id\": \"Adam.JSGenerator\", \"isPrerelease\": false }"
		}

		resp := &http.Response{
			StatusCode: 200,
			Body:       ioutil.NopCloser(strings.NewReader(respBody)),
		}
		return resp, nil
	}
}

func TestDownloadPageNoItems(t *testing.T) {
	ch := make(chan string)
	go downloadPage("https://nuget.org/page_no_items", os.Stderr, withRetries(MockGet(), 5), ch)
	assertEqual(t, "{ \"Items\": [] }", <-ch)
}

func TestDownloadPageHasItems(t *testing.T) {
	ch := make(chan string)
	go downloadPage("https://nuget.org/page_has_items", os.Stderr, withRetries(MockGet(), 5), ch)
	assertEqual(t, "{ \"Items\": [{ \"id\": \"Adam.JSGenerator\", \"isPrerelease\": false }] }", <-ch)
}

func assertEqual(t *testing.T, a interface{}, b interface{}) {
	if a != b {
		t.Fatalf("%s != %s", a, b)
	}
}
