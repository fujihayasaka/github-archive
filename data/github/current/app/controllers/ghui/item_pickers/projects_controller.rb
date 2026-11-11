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
    ApplicationRecord::Ballast,
    only: [:index]

  def index
    variables = {
      owner: params[:owner],
      repo: params[:repo],
      query: params[:query]
    }

    results = execute_server_persisted_query("SearchProjects", variables: variables)
    return unless results

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
