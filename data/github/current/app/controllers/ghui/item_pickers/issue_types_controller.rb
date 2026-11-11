# typed: true
# frozen_string_literal: true

class Ghui::ItemPickers::IssueTypesController < GhuiController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include PullRequests::DatabaseSelection

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
    ApplicationRecord::Ballast,
    only: [:index]

  prepend_around_action :route_reads_to_replicas, only: [:index]

  def index
    variables = {
      owner: params[:owner],
      repo: params[:repo]
    }

    results = execute_server_persisted_query("SearchIssueTypes", variables: variables)
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
        ApplicationRecord::Iam,
        ApplicationRecord::Ballast,
      ], &block)
    else
      block.call
    end
  end

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
