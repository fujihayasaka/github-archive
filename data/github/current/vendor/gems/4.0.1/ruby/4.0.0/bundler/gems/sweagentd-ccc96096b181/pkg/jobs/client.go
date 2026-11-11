// Package jobs provides a Twirp client for the JobsAPI service.
//
// This package can be imported independently without bringing in all of sweagentd's dependencies.
// It only depends on protobuf and twirp libraries.
//
// Example usage:
//
//		import (
//			"github.com/github/sweagentd/pkg/jobs"
//	  	v1 "github.com/github/sweagentd/pkg/jobs/v1"
//			"github.com/github/go-twirp/client/auth"
//		)
//
//		hmacKey := "supersecret"
//		httpClient := &http.Client{}
//		hmacHttpClient, _ := auth.NewRequestHMACSigner(hmacKey, httpClient)
//
//		client := jobs.NewClient("https://sweagentd.example.com", hmacHttpClient)
//		resp, err := client.CreateJob(ctx, &v1.CreateJobRequest{
//			ActorId: 123,
//			RepoId: 456,
//			ProblemStatement: "Fix the bug",
//		})
package jobs

import (
	v1 "github.com/github/sweagentd/pkg/jobs/v1"
	"github.com/twitchtv/twirp"
)

// NewClient creates a new JobsAPI client using protobuf encoding.
func NewClient(baseURL string, httpClient v1.HTTPClient, opts ...twirp.ClientOption) v1.JobsAPI {
	return v1.NewJobsAPIProtobufClient(baseURL, httpClient, opts...)
}
