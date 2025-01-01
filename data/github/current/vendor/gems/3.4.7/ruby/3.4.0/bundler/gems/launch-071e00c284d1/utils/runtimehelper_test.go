package utils

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGetDocsURL(t *testing.T) {
	tests := []struct {
		desc              string
		isEnterprise      bool
		enterpriseVersion string
		expectedUrl       string
	}{
		{
			desc:         "for github.com",
			isEnterprise: false,
			expectedUrl:  "https://docs.github.com/test",
		},
		{
			desc:              "for GHES with version specified in format x.y",
			isEnterprise:      true,
			enterpriseVersion: "3.4",
			expectedUrl:       "https://docs.github.com/enterprise-server@3.4/test",
		},
		{
			desc:              "for GHES with version specified in format x.y.z",
			isEnterprise:      true,
			enterpriseVersion: "3.4.0",
			expectedUrl:       "https://docs.github.com/enterprise-server@3.4/test",
		},
		{
			desc:              "for GHES with version specified in just major format",
			isEnterprise:      true,
			enterpriseVersion: "3",
			expectedUrl:       "https://docs.github.com/enterprise-server@latest/test",
		},
		{
			desc:         "for GHES with version not specified",
			isEnterprise: true,
			expectedUrl:  "https://docs.github.com/enterprise-server@latest/test",
		},
	}
	for _, test := range tests {
		t.Run(test.desc, func(tt *testing.T) {
			runtimeHelper := NewRuntimeHelper(test.isEnterprise, test.enterpriseVersion)
			docsURL := runtimeHelper.GetDocsURL("/test")
			assert.Equal(tt, test.expectedUrl, docsURL)
		})
	}
}
