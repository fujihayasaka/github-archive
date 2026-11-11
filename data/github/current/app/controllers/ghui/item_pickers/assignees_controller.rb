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
    ApplicationRecord::Ballast,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    first = parse_integer_param(:first, default: 100)
    first = [[first, 0].max, 1000].min # clamp between 0 and 1000

    # Determine which query to use based on whether number is provided
    if params[:number].present?
      # Search in issue or PR
      variables = {
        owner: params[:owner],
        name: params[:repo],
        number: params[:number].to_i,
        query: params[:query] || "",
        first: first
      }

      results = execute_server_persisted_query("SearchAssigneesInIssue", variables: variables)
      return unless results
    else
      # Search in repo
      capabilities = params[:capabilities] || ["CAN_BE_ASSIGNED"]
      variables = {
        owner: params[:owner],
        name: params[:repo],
        query: params[:query],
        loginNames: params[:loginNames],
        first: first,
        capabilities: capabilities
      }

      results = execute_server_persisted_query("SearchAssigneesInRepo", variables: variables)
      return unless results
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
