# typed: false
# frozen_string_literal: true

module ProjectsHelper
  # DEPRECATED: helper GraphQL view fragment
  # This is in its own file so that we can autoload it only when needed.
  ProjectColumnAnchorUrl = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    fragment ProjectColumn on ProjectColumn {
      databaseId

      project {
        url
      }
    }
  GRAPHQL
end
