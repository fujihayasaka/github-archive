# typed: false
# frozen_string_literal: true

module ProjectsHelper
  # DEPRECATED: helper GraphQL view fragment
  # This is in its own file so that we can autoload it only when needed.
  ProjectsCursorPaginate = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    fragment on PageInfo {
      endCursor
      hasNextPage
      hasPreviousPage
      startCursor
    }
  GRAPHQL
end
