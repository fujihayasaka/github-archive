# typed: true
# frozen_string_literal: true

class Ghui::ItemPickers::MilestonesController < GhuiController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  allow_verified_fetch only: [:index, :create]

  before_action :parse_json_params
  before_action :validate_index_params, only: [:index]
  before_action :validate_create_params, only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:index, :create]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Ghui::ItemPickers::MilestonesController#create"].freeze

  # the data that is selected via this GraphQL query must be kept in sync with the frontend part
  # that lives in github-ui/packages/item-picker-milestone-tsq/api/milestone.ts
  MILESTONE_QUERY = <<-'GRAPHQL'
    query($owner: String!, $repo: String!, $count: Int!, $query: String) {
      repository(owner: $owner, name: $repo) {
        id
        milestones(first: $count, query: $query, orderBy: {field: UPDATED_AT, direction: DESC}, orderByStates: [OPEN, CLOSED]) {
          nodes {
            id
            title
            closed
            dueOn
            progressPercentage
            url
            closedAt
          }
        }
      }
    }
  GRAPHQL

  def index
    count = parse_integer_param(:count, default: 100)
    count = [[count, 1].max, 1000].min # clamp between 1 and 1000

    results = execute_graphql(MILESTONE_QUERY, "searchMilestones", variables: {
      owner: params[:owner],
      repo: params[:repo],
      query: params[:query],
      count: count
    })

    respond_graphql_payload(results)
  end

  # the data that is selected via this GraphQL query must be kept in sync with the frontend part
  # that lives in github-ui/packages/item-picker-milestone-tsq/api/milestone.ts
  CREATE_MILESTONE_MUTATION = <<-'GRAPHQL'
    mutation($input: CreateMilestoneInput!) {
      createMilestone(input: $input) {
        milestone {
          closed
          closedAt
          dueOn
          id
          progressPercentage
          title
          url
        }
      }
    }
  GRAPHQL

  def create
    results = execute_graphql(CREATE_MILESTONE_MUTATION, "createMilestone", variables: {
      "input" => {
        "repositoryId" => params[:repositoryId],
        "title" => params[:title],
      }
    })

    respond_graphql_payload(results)
  end

  private

  def validate_index_params
    return unless validate_required_params(:owner, :repo)
    validate_integer_param(:count)
  end

  def validate_create_params
    validate_required_params(:repositoryId, :title)
  end

  memoize def owner
    User.find_by_login(params[:owner])
  end

  memoize def repository
    return nil unless owner && params[:repo]
    Repositories.domain.by_name_and_owner(name: params[:repo], owner_id: owner.id, cached: true)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless repository # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    repository
  end

  def target_for_conditional_access
    owner
  end
end
