# typed: true
# frozen_string_literal: true

class Ghui::ItemPickers::ProjectsController < GhuiController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:index]

  before_action :parse_json_params
  before_action :validate_index_params, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    only: [:index]

  # the data that is selected via this GraphQL query must be kept in sync with the frontend part
  # that lives in github-ui/packages/item-picker-project-relay/components/ProjectPicker.tsx
  QUERY = <<-'GRAPHQL'
    query($owner: String!, $repo: String!, $query: String) {
      repository(owner: $owner, name: $repo) {
        projectsV2(first: 5, query: $query, orderBy: {field: RELEVANCE, direction: DESC}, useFullTermQuery: true) {
          nodes {
            ...ProjectPickerRelay
          }
        }
        recentProjects(first: 5) {
          edges {
            node {
              ...ProjectPickerRelay
            }
          }
        }
        owner {
          ... on Organization {
            projectsV2(first: 5, orderBy: {field: RELEVANCE, direction: DESC}, query: $query, useFullTermQuery: true) {
              edges {
                node {
                  ...ProjectPickerRelay
                }
              }
            }
            recentProjects(first: 5) {
              edges {
                node {
                  ...ProjectPickerRelay
                }
              }
            }
          }
          ... on User {
            projectsV2(first: 5, orderBy: {field: RELEVANCE, direction: DESC}, query: $query, useFullTermQuery: true) {
              edges {
                node {
                  ...ProjectPickerRelay
                }
              }
            }
            recentProjects(first: 5) {
              edges {
                node {
                  ...ProjectPickerRelay
                }
              }
            }
          }
        }
      }
    }

    fragment ProjectPickerRelay on ProjectV2 {
      id
      title
      closed
      number
      url
      viewerCanUpdate
      hasReachedItemsLimit
      __typename
    }
  GRAPHQL

  def index
    results = execute_graphql(QUERY, "searchProjects", variables: {
      owner: params[:owner],
      repo: params[:repo],
      query: params[:query]
    })

    respond_graphql_payload(results)
  end

  private

  def validate_index_params
    validate_required_params(:owner, :repo)
  end

  memoize def owner
    User.find_by_login(params[:owner])
  end

  memoize def repository
    return nil unless owner && params[:repo]
    Repositories.domain.by_name_and_owner(name: params[:repo], owner_id: owner.id)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless repository # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    repository
  end

  def target_for_conditional_access
    owner
  end
end
