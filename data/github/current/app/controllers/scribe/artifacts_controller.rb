# typed: true
# frozen_string_literal: true

require "scribe"
require "monolith-twirp-scribe-artifacts"

class Scribe::ArtifactsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create, :update, :destroy]

  before_action :parse_json_params, only: [:create, :update]
  before_action :login_required
  before_action :require_feature_flag
  before_action :load_resource
  before_action :ensure_resource_enabled
  before_action :ensure_user_can_read, only: [:index]
  before_action :ensure_user_can_write, only: [:create, :update, :destroy]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Scribe::ArtifactsController#create",
    "Scribe::ArtifactsController#update",
    "Scribe::ArtifactsController#destroy",
  ].freeze

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories

  def index
    return render_storage_unavailable unless scribe_enabled?

    response = GitHub.scribe_client.list_artifacts(
      user: current_user,
      resource_type: resource_type,
      resource_id: resource_id,
      type: params[:type].presence,
    )

    creators = User.where(id: response.artifacts.map(&:actor_id).uniq).index_by(&:id)
    body_context = artifact_body_context
    render json: response.artifacts.map { |artifact|
      artifact_json(artifact, body_context:, creator: creators[artifact.actor_id])
    }
  rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
    GitHub.dogstats.increment("scribe.artifacts.list.error", tags: ["error_class:#{e.class.name}"])
    render_storage_temporarily_unavailable
  end

  def create
    return render json: { message: "name is required" }, status: :unprocessable_entity if params[:name].blank?
    return render_storage_unavailable unless scribe_enabled?

    response = GitHub.scribe_client.create_artifact(
      user: current_user,
      resource_type: resource_type,
      resource_id: resource_id,
      type: params[:type].presence || "generic",
      name: params[:name],
      body: params[:body],
    )

    artifact = response.artifact
    return render json: { message: "Failed to create artifact" }, status: :internal_server_error unless artifact

    creator = User.find_by(id: artifact.actor_id) || current_user
    render json: artifact_json(artifact, body_context: artifact_body_context, creator: creator), status: :created
  rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
    GitHub.dogstats.increment("scribe.artifacts.create.error", tags: ["error_class:#{e.class.name}"])
    render_storage_temporarily_unavailable
  end

  def destroy
    return render_storage_unavailable unless scribe_enabled?

    response = GitHub.scribe_client.destroy_artifact(
      user: current_user,
      resource_type: resource_type,
      resource_id: resource_id,
      number: params[:id].to_i,
    )

    return render json: { message: "Artifact not found" }, status: :not_found unless response.success

    render json: { number: params[:id].to_i, deleted: true }
  rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
    GitHub.dogstats.increment("scribe.artifacts.destroy.error", tags: ["error_class:#{e.class.name}"])
    render_storage_temporarily_unavailable
  end

  def update
    has_name = params.key?(:name)
    has_body = params.key?(:body)
    return render json: { message: "name or body is required" }, status: :unprocessable_entity unless has_name || has_body
    return render_storage_unavailable unless scribe_enabled?

    response = GitHub.scribe_client.update_artifact(
      user: current_user,
      resource_type: resource_type,
      resource_id: resource_id,
      number: params[:id].to_i,
      name: has_name ? params[:name] : nil,
      body: has_body ? params[:body] : nil,
    )

    artifact = response.artifact
    return render json: { message: "Artifact not found" }, status: :not_found unless artifact

    creator = User.find_by(id: artifact.actor_id) || current_user
    render json: artifact_json(artifact, body_context: artifact_body_context, creator: creator)
  rescue Scribe::Client::Error, Faraday::ConnectionFailed => e
    GitHub.dogstats.increment("scribe.artifacts.update.error", tags: ["error_class:#{e.class.name}"])
    render_storage_temporarily_unavailable
  end

  private

  def require_feature_flag
    render_404 unless FeatureFlag.vexi.enabled?(:scribe_artifacts_api, current_user, default: false)
  end

  def load_resource
    @resource = case resource_type
    when "issue"
      Issue.find_by(id: resource_id)
    end

    render_404 unless @resource
  end

  def ensure_resource_enabled
    return unless issue_resource?

    repository = resource.repository
    if resource.pull_request_id
      return if repository.has_pull_requests?

      return render json: { message: "Pull requests are disabled for this repo" }, status: :gone
    end

    return if repository.has_issues?

    render json: { message: "Issues are disabled for this repo" }, status: :gone
  end

  def ensure_user_can_read
    render_404 unless issue_resource? && resource.repository.resources.issues.readable_by?(current_user)
  end

  def ensure_user_can_write
    render_404 unless issue_resource? && resource.repository.resources.issues.writable_by?(current_user)
  end

  def resource
    T.must(@resource)
  end

  def resource_type
    params[:resource_type].to_s
  end

  def resource_id
    params[:resource_id].to_i
  end

  def issue_resource?
    resource_type == "issue" && resource.is_a?(Issue)
  end

  def scribe_enabled?
    GitHub.scribe_enabled?(user: current_user)
  end

  def render_storage_unavailable
    render json: { message: "Artifact storage is not available" }, status: :service_unavailable
  end

  def render_storage_temporarily_unavailable
    render json: { message: "Artifact storage is temporarily unavailable" }, status: :service_unavailable
  end

  def artifact_json(artifact, body_context:, creator:)
    {
      id: artifact.id,
      number: artifact.number,
      type: artifact.type,
      name: artifact.name,
      body: artifact.body,
      body_html: body_html_for_artifact(artifact, body_context:, creator:),
      created_at: artifact.created_at&.to_time&.utc&.iso8601,
      updated_at: artifact.updated_at&.to_time&.utc&.iso8601,
      creator: creator && {
        login: creator.display_login,
        id: creator.id,
      },
    }
  end

  def body_html_for_artifact(artifact, body_context:, creator:)
    body = artifact.body
    return nil if body.nil?

    GitHub::Goomba::MarkdownPipeline.to_html(body, body_context.merge(current_user: creator, viewer: current_user))
  end

  def artifact_body_context
    return {} unless issue_resource?

    resource.async_body_context.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

    @resource || current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    @resource || current_user
  end
end
