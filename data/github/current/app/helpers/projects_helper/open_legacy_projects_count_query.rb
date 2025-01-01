# typed: true
# frozen_string_literal: true

module ProjectsHelper
  OpenLegacyProjectsCountQuery = PlatformClient.parse <<-'GRAPHQL'
  query($projectOwnerId: ID!, $query: String) {
    node(id: $projectOwnerId) {
      ... on ProjectOwner {
        openProjects: projects(search: $query, states:[OPEN]) {
          totalCount
        }
      }
    }
  }
  GRAPHQL
end
