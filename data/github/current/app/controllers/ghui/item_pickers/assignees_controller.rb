# typed: true
# frozen_string_literal: true

class Ghui::ItemPickers::AssigneesController < GhuiController
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
    ApplicationRecord::Permissions,
    only: [:index]

  ASSIGNEES_IN_REPO = <<-'GRAPHQL'
    query (
      $owner: String!
      $name: String!
      $query: String
      $loginNames: String
      $first: Int!
      $capabilities: [RepositorySuggestedActorFilter!]!
    ) {
      repository(owner: $owner, name: $name) {
        suggestedActors(first: $first, query: $query, loginNames: $loginNames, capabilities: $capabilities) {
          nodes {
            __typename
            id
            login
            name
            profileResourcePath
            avatarUrl(size: 64)
            ... on Bot {
              isCopilot
              isAgent
              displayName
            }
          }
          totalCount
        }
      }
    }
  GRAPHQL

  ASSIGNEES_IN_ISSUE = <<-'GRAPHQL'
    query (
      $owner: String!
      $name: String!
      $number: Int!
      $query: String!
      $first: Int!
    ) {
      repository(owner: $owner, name: $name) {
        issueOrPullRequest(number: $number) {
          ... on Assignable {
            suggestedActors(first: $first, query: $query) {
              nodes {
                __typename
                ... on User {
                  id
                  login
                  name
                  profileResourcePath
                  avatarUrl(size: 64)
                }
                ... on Bot {
                  id
                  login
                  name
                  profileResourcePath
                  avatarUrl(size: 64)
                  isCopilot
                  isAgent
                  displayName
                }
                ... on Mannequin {
                  id
                  login
                  name: login
                  profileResourcePath: url
                  avatarUrl(size: 64)
                }
                ... on Organization {
                  id
                  login
                  name
                  profileResourcePath: url
                  avatarUrl(size: 64)
                }
              }
              totalCount
            }
          }
        }
      }
    }
  GRAPHQL

  def index
    first = parse_integer_param(:first, default: 100)
    first = [[first, 0].max, 1000].min # clamp between 0 and 1000

    # Determine which query to use based on whether number is provided
    if params[:number].present?
      # Search in issue or PR
      results = execute_graphql(ASSIGNEES_IN_ISSUE, "searchAssigneesInIssue", variables: {
        owner: params[:owner],
        name: params[:repo],
        number: params[:number].to_i,
        query: params[:query] || "",
        first: first
      })
    else
      # Search in repo
      capabilities = params[:capabilities] || ["CAN_BE_ASSIGNED"]
      results = execute_graphql(ASSIGNEES_IN_REPO, "searchAssigneesInRepo", variables: {
        owner: params[:owner],
        name: params[:repo],
        query: params[:query],
        loginNames: params[:loginNames],
        first: first,
        capabilities: capabilities
      })
    end

    respond_graphql_payload(results)
  end

  private

  def validate_index_params
    return unless validate_required_params(:owner, :repo)
    return unless validate_integer_param(:first)

    if params[:number].present?
      return unless validate_integer_param(:number)
    end

    # Check that query and loginNames are not both provided for repo search
    if params[:number].blank? && params[:query].present? && params[:loginNames].present?
      respond_error(:bad_request, "Cannot provide both query and loginNames parameters")
      return false
    end

    true
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
