# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::CustomModelPipelineRepositoriesController < Orgs::CopilotSettings::BaseController
  extend T::Sig
  extend GitHub::Memoizer

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ReactHelper

  # Turn off CSRF for React.
  allow_verified_fetch only: [:show]

  before_action :parse_json_params, only: [:show]

  javascript_bundle :settings
  javascript_bundle :copilot

  PipelineRepo = T.type_alias do
    {
      id: Integer,
      name: String,
      nameWithOwner: String,
      isInOrganization: T::Boolean,
      owner: {
        avatarUrl: String
      }
    }
  end

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-custom-models"
  end

  sig { void }
  def index
    current_pipeline_repo_ids = T.must(current_pipeline).repositories.map(&:id)
    limit_by = T.cast(ActiveRecord::Base.sanitize_sql_like(params[:limit_by]).to_i, Integer)
    if limit_by > 0
      pipeline_repos = current_organization.repositories.where(id: current_pipeline_repo_ids).limit(limit_by).sort_by(&:name)
    else
      pipeline_repos = current_organization.repositories.where(id: current_pipeline_repo_ids).sort_by(&:name)
    end

    data = create_hash(pipeline_repos)

    render json: { data: data }
  end

  sig { void }
  def search # rubocop:todo GitHub/UseRestfulActions
    search_string = ActiveRecord::Base.sanitize_sql_like(params[:q])
    current_pipeline_repo_ids = T.must(current_pipeline).repositories.map(&:id)
    pipeline_repos = current_organization.repositories.where(id: current_pipeline_repo_ids).where("name like ?", "%#{search_string}%").limit(15).sort_by(&:name)

    data = create_hash(pipeline_repos)

    render json: { data: data }
  end

  private

  sig { returns(T.nilable(Orca::Pipeline)) }
  memoize def current_pipeline
    pipeline = Orca::Pipeline.fetch_by_id(params[:pipeline_id])
    render_404 if pipeline.nil?
    pipeline
  end

  sig { params(pipeline_repos: T::Array[Repository]).returns(T::Array[PipelineRepo]) }
  def create_hash(pipeline_repos)
    pipeline_repos.map do |pr|
      {
        id: T.must(pr.id),
        name: T.must(pr.name),
        nameWithOwner: pr.name_with_display_owner,
        isInOrganization: pr.in_organization?,
        owner: {
          avatarUrl: current_organization.primary_avatar_url
        }
      }
    end
  end
end
