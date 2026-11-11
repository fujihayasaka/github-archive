# typed: true
# frozen_string_literal: true

class Ghui::ItemPickers::MilestonesController < GhuiController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include PullRequests::DatabaseSelection

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
    ApplicationRecord::Ballast,
    only: [:index, :create]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Ghui::ItemPickers::MilestonesController#create"].freeze

  prepend_around_action :route_reads_to_replicas, only: [:index]

  def index
    count = parse_integer_param(:count, default: 100)
    count = [[count, 1].max, 1000].min # clamp between 1 and 1000

    variables = {
      owner: params[:owner],
      repo: params[:repo],
      query: params[:query],
      count: count
    }

    results = execute_server_persisted_query("SearchMilestones", variables: variables)
    return unless results

    respond_graphql_payload(results)
  end

  def create
    variables = {
      "input" => {
        "repositoryId" => params[:repositoryId],
        "title" => params[:title],
      }
    }

    results = execute_server_persisted_query("CreateMilestone", variables: variables)
    return unless results

    respond_graphql_payload(results)
  end

  private

  def route_reads_to_replicas(&block)
    if FeatureFlag.vexi.enabled?(:web_read_from_replicas_controller, ControllerActor.new(self.class), default: false)
      use_replica_clusters([
        ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Repositories,
        ApplicationRecord::IssuesPullRequests,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Ballast,
      ], &block)
    else
      block.call
    end
  end

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
