package tokens

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewInstallationPermissions_Default(t *testing.T) {
	perms := NewInstallationPermissions("")
	expected := &InstallationPermissions{
		Actions:            NoneAccess,
		Attestations:       NoneAccess,
		Checks:             NoneAccess,
		Contents:           NoneAccess,
		Deployments:        NoneAccess,
		Issues:             NoneAccess,
		Discussions:        NoneAccess,
		Metadata:           ReadAccess,
		Packages:           NoneAccess,
		Pages:              NoneAccess,
		PullRequests:       NoneAccess,
		RepositoryProjects: NoneAccess,
		Statuses:           NoneAccess,
		SecurityEvents:     NoneAccess,
	}
	assert.Equal(t, expected, perms)
}

func TestNewInstallationPermissions_LimitedReadPermissions(t *testing.T) {
	perms := NewInstallationPermissions(LimitedReadPermissions)
	expected := &InstallationPermissions{
		Actions:            NoneAccess,
		Attestations:       NoneAccess,
		Checks:             NoneAccess,
		Contents:           ReadAccess,
		Deployments:        NoneAccess,
		Issues:             NoneAccess,
		Discussions:        NoneAccess,
		Metadata:           ReadAccess,
		Packages:           ReadAccess,
		Pages:              NoneAccess,
		PullRequests:       NoneAccess,
		RepositoryProjects: NoneAccess,
		Statuses:           NoneAccess,
		SecurityEvents:     NoneAccess,
	}
	assert.Equal(t, expected, perms)
}

func TestNewInstallationPermissions_ReadPermissions(t *testing.T) {
	perms := NewInstallationPermissions(ReadPermissions)
	expected := &InstallationPermissions{
		Actions:            ReadAccess,
		Attestations:       ReadAccess,
		Checks:             ReadAccess,
		Contents:           ReadAccess,
		Deployments:        ReadAccess,
		Issues:             ReadAccess,
		Discussions:        ReadAccess,
		Metadata:           ReadAccess,
		Packages:           ReadAccess,
		Pages:              ReadAccess,
		PullRequests:       ReadAccess,
		RepositoryProjects: ReadAccess,
		Statuses:           ReadAccess,
		SecurityEvents:     ReadAccess,
	}
	assert.Equal(t, expected, perms)
}

func TestNewInstallationPermissions_WritePermissions(t *testing.T) {
	perms := NewInstallationPermissions(WritePermissions)
	expected := &InstallationPermissions{
		Actions:            WriteAccess,
		Attestations:       WriteAccess,
		Checks:             WriteAccess,
		Contents:           WriteAccess,
		Deployments:        WriteAccess,
		Issues:             WriteAccess,
		Discussions:        WriteAccess,
		Metadata:           ReadAccess,
		Packages:           WriteAccess,
		Pages:              WriteAccess,
		PullRequests:       WriteAccess,
		RepositoryProjects: WriteAccess,
		Statuses:           WriteAccess,
		SecurityEvents:     WriteAccess,
	}
	assert.Equal(t, expected, perms)
}
