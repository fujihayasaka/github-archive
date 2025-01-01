package observability

import "github.com/github/launch/observability/statter"

func ErrorTag(tags statter.Tags, err error) statter.Tags {
	if err == nil {
		return tags
	}
	if tags == nil {
		tags = statter.Tags{}
	}
	tags["error"] = "true"
	return tags
}
