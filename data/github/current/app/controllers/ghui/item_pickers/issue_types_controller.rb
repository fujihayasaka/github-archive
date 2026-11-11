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
  ORGANIZATION_QUERY = <<-'GRAPHQL'
    query($owner: String!) {
      organization(login: $owner) {
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
    results = execute_graphql(ORGANIZATION_QUERY, "searchIssueTypes", variables: {
      owner: params[:owner]
    })

    respond_graphql_payload(results)
  end

  private

  def validate_index_params
    validate_required_params(:owner)
  end

  memoize def organization
    Organization.find_by_login(params[:owner])
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless organization # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    organization
  end

  def target_for_conditional_access
    organization
  end
end
