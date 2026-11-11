# typed: true
# frozen_string_literal: true

class Ghui::ItemPickers::IssueTypesController < GhuiController # rubocop:todo GitHub/ControllersShouldHaveTests
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:index]

  before_action :parse_json_params
  before_action :validate_index_params, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:index]

  # the data that is selected via this GraphQL query must be kept in sync with the frontend part
  # that lives in github-ui/packages/item-picker-issue-type-tsq/components/IssueTypePicker.tsx
  #
  # Repository-based query: Uses repository.issueTypes
  # - Works for outside collaborators (non-org members with repo access)
  # - Works for org members with repository access
  #
  # See: https://github.com/github/issues/issues/19249
  REPOSITORY_QUERY = <<-'GRAPHQL'
    query($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
        issueTypes(first: 25) {
          edges {
            node {
              id
              name
              isEnabled
              description
              color
              pinnedFields {
                __typename
                ... on IssueFieldText {
                  id
                  name
                  dataType
                }
                ... on IssueFieldSingleSelect {
                  id
                  name
                  dataType
                }
                ... on IssueFieldDate {
                  id
                  name
                  dataType
                }
                ... on IssueFieldNumber {
                  id
                  name
                  dataType
                }
              }
            }
          }
          totalCount
        }
      }
    }
  GRAPHQL

  def index
    results = execute_graphql(REPOSITORY_QUERY, "searchIssueTypes", variables: {
      owner: params[:owner],
      repo: params[:repo]
    })

    respond_graphql_payload(results)
  end

  private

  def validate_index_params
    validate_required_params(:owner, :repo)
  end

  memoize def repository
    Repository.find_by(owner_login: params[:owner], name: params[:repo])
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless repository # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    repository
  end

  def target_for_conditional_access
    repository
  end
end
