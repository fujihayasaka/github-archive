// Package semconv provides semantic conventions for KVPs as per https://otel.githubapp.com/.
package semconv

import (
	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

// See https://opentelemetry.io/docs/specs/semconv/messaging/kafka/

// MessagingOperationType returns a field for messaging operation type.
func MessagingOperationType(v string) zapcore.Field {
	return kvp.String("messaging.operation.type", v)
}

// MessagingDestinationName returns a field for messaging destination name.
func MessagingDestinationName(v string) zapcore.Field {
	return kvp.String("messaging.destination.name", v)
}

// MessagingDestinationPartitionID returns a field for messaging destination partition ID.
func MessagingDestinationPartitionID(v int32) zapcore.Field {
	return kvp.Int32("messaging.destination.partition.id", v)
}

// MessagingKafkaMessageOffset returns a field for Kafka message offset.
func MessagingKafkaMessageOffset(v int64) zapcore.Field {
	return kvp.Int64("messaging.kafka.message.offset", v)
}

// MessagingMessageID returns a field for message ID.
func MessagingMessageID(v string) zapcore.Field {
	return kvp.String("messaging.message.id", v)
}

// Method returns a field for the method being executed.
func Method(v string) zapcore.Field {
	return kvp.String("gh.osslicensecompliance.method", v)
}

// EnterpriseID returns a field for the enterprise ID.
func EnterpriseID(v uint64) zapcore.Field {
	return kvp.Uint64("gh.osslicensecompliance.repository-check-request.enterprise_id", v)
}

// OrganizationID returns a field for the organization ID.
func OrganizationID(v uint64) zapcore.Field {
	return kvp.Uint64("gh.osslicensecompliance.repository-check-request.organization_id", v)
}

// RepositoryID returns a field for the repository ID.
func RepositoryID(v uint64) zapcore.Field {
	return kvp.Uint64("gh.osslicensecompliance.repository-check-request.repository_id", v)
}

// PullRequestID returns a field for the pull request ID.
func PullRequestID(v uint64) zapcore.Field {
	return kvp.Uint64("gh.osslicensecompliance.repository-check-request.pull_request_id", v)
}

// PullRequestNumber returns a field for the pull request number.
func PullRequestNumber(v uint32) zapcore.Field {
	return kvp.Uint32("gh.osslicensecompliance.repository-check-request.pull_request_number", v)
}

// CommitSHA returns a field for the commit SHA.
func CommitSHA(v string) zapcore.Field {
	return kvp.String("gh.osslicensecompliance.repository-check-request.commitsha", v)
}

// BaseSHA returns a field for the base SHA.
func BaseSHA(v string) zapcore.Field {
	return kvp.String("gh.osslicensecompliance.repository-check-request.basesha", v)
}

// AlertNumber returns a field for the alert number.
func AlertNumber(v uint32) zapcore.Field {
	return kvp.Uint32("gh.osslicensecompliance.alert.number", v)
}

// SPDXExpression returns a field for an SPDX expression.
func SPDXExpression(v string) zapcore.Field {
	return kvp.String("gh.osslicensecompliance.alert.spdx_expression", v)
}

// DistributionContext returns a field for distribution context.
func DistributionContext(v string) zapcore.Field {
	return kvp.String("gh.osslicensecompliance.distribution_context", v)
}

// CheckJobID returns a field for the check job ID.
func CheckJobID(v uint64) zapcore.Field {
	return kvp.Uint64("gh.osslicensecompliance.check_job.id", v)
}

// RepoCheckRequestFields returns all the standard repository check request fields.
// This is a convenience function to avoid repeating the same fields in multiple places.
func RepoCheckRequestFields(enterpriseID, organizationID, repositoryID, pullRequestID uint64, pullRequestNumber uint32, commitSHA, baseSHA string) []zapcore.Field {
	return []zapcore.Field{
		EnterpriseID(enterpriseID),
		OrganizationID(organizationID),
		RepositoryID(repositoryID),
		PullRequestID(pullRequestID),
		PullRequestNumber(pullRequestNumber),
		CommitSHA(commitSHA),
		BaseSHA(baseSHA),
	}
}
