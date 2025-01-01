package azp

import (
	"fmt"
	"strings"
)

type Version struct {
	Major int64 `json:"major"`
	Minor int64 `json:"minor"`
	Patch int64 `json:"patch"`
}

func (v *Version) String() string {
	return fmt.Sprintf("v%d.%d.%d", v.Major, v.Minor, v.Patch)
}

type Download struct {
	Type          string  `json:"type"`
	Platform      string  `json:"platform"`
	Version       Version `json:"version"`
	DownloadURL   string  `json:"downloadUrl"`
	Filename      string  `json:"filename"`
	DownloadToken string  `json:"token"`
	Sha256Hash    string  `json:"hashValue"`
}

func (d *Download) GetOS() (string, error) {
	res := strings.Split(d.Platform, "-")
	if len(res) != 2 {
		return "", fmt.Errorf("Expected platform string %s to have the signature os-arch", d.Platform)
	}
	return res[0], nil
}

func (d *Download) GetArchitecture() (string, error) {
	res := strings.Split(d.Platform, "-")
	if len(res) != 2 {
		return "", fmt.Errorf("Expected platform string %s to have the signature os-arch", d.Platform)
	}
	return res[1], nil
}

type DownloadsList struct {
	Count int64       `json:"count"`
	Value []*Download `json:"value"`
}
