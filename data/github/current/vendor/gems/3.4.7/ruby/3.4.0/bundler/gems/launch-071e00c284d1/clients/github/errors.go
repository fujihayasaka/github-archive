package github

import (
	"strings"

	"github.com/github/go-kvp"
	errs "github.com/pkg/errors"

	"github.com/github/launch/observability/kvperrors"
	terrors "github.com/github/launch/types/errors"
)

// ErrorsFromResponse creates errors from the given GraphQL response.
func errorsFromResponse(resp *GraphQLResponse) error {
	if len(resp.Errors) == 0 {
		return nil
	}

	// Return a custom error when the error indicates a resource was not found:
	notFoundType := resp.Errors[0].Type == "NOT_FOUND"
	notFoundValidation := resp.Errors[0].Type == "VALIDATION" && strings.HasPrefix(resp.Errors[0].Message, "No commit found for SHA: ")
	if notFoundType || notFoundValidation {
		return terrors.NewNotFoundError(kvperrors.With("Not Found",
			kvp.String("graphql.operation.name", "GraphQL::NotFound"),
			kvp.String("gh.launch.graphql_error.type", resp.Errors[0].Type),
			kvp.String("gh.launch.graphql_error.message", resp.Errors[0].Message),
		))
	}

	forbiddenType := resp.Errors[0].Type == "FORBIDDEN"
	if forbiddenType {
		return terrors.NewForbiddenError(kvperrors.With(resp.Errors[0].Message,
			kvp.String("graphql.operation.name", "GraphQL::Forbidden"),
			kvp.String("gh.launch.graphql_error.type", resp.Errors[0].Type),
			kvp.String("gh.launch.graphql_error.message", resp.Errors[0].Message),
		))
	}

	return kvperrors.WrapWith(errs.Errorf("Unexpected error: %#v", resp.Errors),
		kvp.String("graphql.operation.name", "GraphQL::Error"),
	)
}

func convertGraphQLError(err error) error {
	if err == nil {
		return nil
	}

	resourceNotAccessible := strings.HasPrefix(err.Error(), "Resource not accessible")
	if resourceNotAccessible {
		return terrors.NewForbiddenError(err)
	}

	// Return a custom error when the error indicates a resource was not found:
	commitNotFoundValidation := strings.HasPrefix(err.Error(), "No commit found for SHA: ")
	globalIDNotResolvable := strings.HasPrefix(err.Error(), "Could not resolve to a node with the global id of ")

	if globalIDNotResolvable || commitNotFoundValidation {
		return terrors.NewNotFoundError(kvperrors.With("not found", kvp.String("graphql.operation.name", "GraphQL::NotFound")))
	}

	// Create Check Suite has a unique error if the head repository is not found
	// https://github.com/github/actions-relaunch/issues/1201
	// https://github.com/github/github/blob/57627f80e3c4222f0ca68dccde387494b5c54ea6/app/platform/mutations/create_check_suite.rb#L73-L76
	if strings.HasPrefix(err.Error(), "Could not resolve to Repository") {
		return terrors.NewNotFoundError(kvperrors.With("not found", kvp.String("graphql.operation.name", "GraphQL::NotFound")))
	}

	return kvperrors.WrapWith(err, kvp.String("graphql.operation.name", "GraphQL::Error"))

}
