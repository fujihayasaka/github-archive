# typed: true
# frozen_string_literal: true

require "react_payload"

class Orgs::ArtifactRegistryController < Orgs::Controller
  include Site::BreadcrumbDependency

  before_action :ensure_logged_in
  before_action :ensure_feature_enabled
  before_action :ensure_org_member
  before_action :load_artifact, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::ArtifactRegistry

  def index
    artifacts = ArtifactMetadata.artifacts_by_org_id(
      org_id: current_organization.id,
      limit: 25
    )
    total_count = ArtifactMetadata.artifact_count_by_org_id(
      org_id: current_organization.id
    )

    respond_with_react(
      app_name: "artifact-registry",
      payload: ArtifactRegistryIndexRoutePayload.new(
        artifacts: artifacts,
        total_count: total_count,
      ),
      title: "Artifact Registry",
      page_data: {
        selected_link: :packages,
      },
    )
  end

  def show
    deployments = ArtifactDeploymentRecord.deployments_by_artifact_id(params[:id].to_i)

    # Check if user has permission to view the repository
    unless @artifact_metadata.repository&.readable_by?(current_user)
      render_404 and return
    end

    first_record = @artifact_metadata.storage_records.first
    storage_record = if first_record
      {
        id: first_record.id,
        registry_url: first_record.registry_url,
        registry_repository_name: first_record.registry_repository_name,
        artifact_url: first_record.artifact_url,
        artifact_path: first_record.artifact_path,
        source_registry: first_record.source_registry,
        created_at: first_record.created_at,
        updated_at: first_record.updated_at,
        status: @artifact_metadata.status,
      }
    end

    artifact_hash = {
      artifact_metadata_id: @artifact_metadata.id,
      owner_id: @artifact_metadata.owner_id,
      artifact_name: @artifact_metadata.name,
      version: @artifact_metadata.version,
      digest: @artifact_metadata.digest,
      created_at: @artifact_metadata.created_at,
      updated_at: @artifact_metadata.updated_at,
      attestation_id: @artifact_metadata.attestation_id,
      repository_id: @artifact_metadata.repository_id,
      repository_name: @artifact_metadata.repository.name,
      repository_is_private: !@artifact_metadata.repository.public,
      source_registry: first_record&.source_registry,
      status: @artifact_metadata.status,
    }

    respond_with_react(
      app_name: "artifact-registry",
      payload: ArtifactRegistryShowRoutePayload.new(
        artifact: artifact_hash,
        deployments: deployments,
        storage_record: storage_record,
      ),
      title: "Artifact Details",
      page_data: {
        selected_link: :packages,
      },
    )
  end

  private

  sig { void }
  def load_artifact
    @artifact_metadata = ArtifactMetadata.includes(:repository, :storage_records).find(params[:id])
    render_404 unless @artifact_metadata.owner_id == current_organization.id
    render_404 if @artifact_metadata.repository.nil?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  sig { void }
  def ensure_logged_in
    render_404 unless logged_in?
  end

  sig { void }
  def ensure_feature_enabled
    render_404 unless current_organization&.feature_flag_enabled?(:artifact_registry_ui, default: false)
  end

  sig { void }
  def ensure_org_member
    render_404 unless current_organization&.member?(current_user)
  end

  class ArtifactRegistryIndexRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "artifactRegistryIndexRoute"
    end

    sig { params(artifacts: T::Array[T::Hash[Symbol, T.untyped]], total_count: Integer).void }
    def initialize(artifacts:, total_count:)
      @artifacts = artifacts
      @total_count = total_count
    end

    def payload
      {
        artifacts: @artifacts,
        totalCount: @total_count,
      }
    end
  end

  class ArtifactRegistryShowRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "artifactRegistryShowRoute"
    end

    sig { params(artifact: T::Hash[Symbol, T.untyped], deployments: T::Array[T::Hash[Symbol, T.untyped]], storage_record: T.nilable(T::Hash[Symbol, T.untyped])).void }
    def initialize(artifact:, deployments:, storage_record:)
      @artifact = artifact
      @deployments = deployments
      @storage_record = storage_record
    end

    def payload
      {
        artifact: @artifact,
        deployments: @deployments,
        storageRecord: @storage_record,
      }
    end
  end
end
