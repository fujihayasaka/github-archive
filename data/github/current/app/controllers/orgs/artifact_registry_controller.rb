# typed: true
# frozen_string_literal: true

require "react_payload"

class Orgs::ArtifactRegistryController < Orgs::Controller
  include Site::BreadcrumbDependency

  before_action :ensure_feature_enabled
  before_action :require_org_membership, only: [:index]
  before_action :organization_read_required, only: [:show]
  before_action :load_artifact, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::ArtifactRegistry,
    only: [:index, :show]

  def index
    # Offset-based pagination using page number
    page = page_param || 1
    per_page = per_page_param || 25

    artifacts = ArtifactMetadata.artifacts_by_org_id(
      org_id: current_organization.id,
      per_page: per_page,
      page: page,
      sort: parsed_query.qualifiers[:sort].must&.last
    )
    artifacts_with_app_name = artifacts.map do |artifact|
      app_name = get_app_name(artifact)
      artifact.merge(app_name: app_name)
    end

    total_count = ArtifactMetadata.artifact_count_by_org_id(org_id: current_organization.id)
    total_pages = (total_count / per_page.to_f).ceil

    result = {
      artifacts: artifacts_with_app_name,
      page_info: {
        has_next_page: page < total_pages,
        has_previous_page: page > 1,
        page_size: per_page,
        current_page: page,
        total_count: total_count,
        total_pages: total_pages,
        offset: (page - 1) * per_page,
      }
    }

    # TODO: wrap by an authorizer to filter out artifacts that the user cannot view
    # Filter artifacts by repository access, batch loading repositories to avoid N+1 queries
    repository_ids = result[:artifacts].map { |artifact| artifact[:repository_id] }.uniq
    repositories = Repository.where(id: repository_ids).index_by(&:id)
    visible_artifacts = result[:artifacts].select do |artifact|
      repo = repositories[artifact[:repository_id]]
      repo && repo.readable_by?(current_user)
    end

    respond_with_react(
      app_name: "artifact-registry",
      payload: ArtifactRegistryIndexRoutePayload.new(
        artifacts: visible_artifacts,
        page_info: result[:page_info]
      ),
      title: "Artifact Registry",
      page_data: {
        selected_link: :packages,
      },
    )
  end

  def show
    # Deployment pagination params (using deployment_ prefix to avoid collision)
    deployment_page = deployment_page_param || 1
    deployment_per_page = deployment_per_page_param || 20

    deployments = ArtifactDeploymentRecord.deployments_by_artifact_id_paginated(
      artifact_metadata_id: params[:id].to_i,
      page: deployment_page,
      per_page: deployment_per_page
    )

    deployment_total_count = ArtifactDeploymentRecord.deployment_count_by_artifact_id(
      artifact_metadata_id: params[:id].to_i
    )
    deployment_total_pages = (deployment_total_count / deployment_per_page.to_f).ceil

    deployment_page_info = {
      page: deployment_page,
      per_page: deployment_per_page,
      total_count: deployment_total_count,
      total_pages: deployment_total_pages,
      has_next_page: deployment_page < deployment_total_pages,
      has_previous_page: deployment_page > 1,
    }

    # Check if user has permission to view the repository
    unless @artifact_metadata.repository&.readable_by?(current_user)
      render_404 and return
    end

    first_record = @artifact_metadata.storage_records.first
    app_name = first_record ? get_app_name(first_record) : nil
    storage_record = if first_record
      {
        id: first_record.id,
        registry_url: first_record.registry_url,
        registry_repository_name: first_record.registry_repository_name,
        artifact_url: first_record.artifact_url,
        artifact_path: first_record.artifact_path,
        app_name: app_name,
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
      app_name: app_name,
      source_registry: first_record&.source_registry,
      status: @artifact_metadata.status,
    }

    attestations = fetch_attestations_by_digest(
      repository: @artifact_metadata.repository,
      digest: @artifact_metadata.digest,
    )

    respond_with_react(
      app_name: "artifact-registry",
      payload: ArtifactRegistryShowRoutePayload.new(
        artifact: artifact_hash,
        attestations: attestations,
        deployments: deployments,
        storage_record: storage_record,
        deployment_page_info: deployment_page_info,
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

  # if the request to create a storage record was made by an app/integration,
  # return the integration's name. Note that integrations are referred to as apps in
  # public documentation so this function refers to the app name
  sig { params(record: T.any(ArtifactStorageRecord, T::Hash[Symbol, T.untyped])).returns(T.nilable(String)) }
  def get_app_name(record)
    integration_id = nil
    if record.is_a?(ArtifactStorageRecord)
      integration_id = record.integration_id
    else
      integration_id = record[:integration_id]
    end
    return nil if integration_id.nil?

    integration = Integration.find_by(id: integration_id)
    integration&.name
  end

  sig { void }
  def ensure_feature_enabled
    render_404 unless this_organization&.feature_flag_enabled?(:artifact_registry_ui, default: false)
  end

  sig { void }
  def require_org_membership
    return if viewer_is_member_of_this_org?

    # If the user is not a member of the organization,
    # render an empty index page
    respond_with_react(
      app_name: "artifact-registry",
      payload: ArtifactRegistryIndexRoutePayload.new(
        artifacts: [],
        page_info: {
          has_next_page: false,
          has_previous_page: false,
          page_size: 0,
          current_page: 1,
          total_count: 0,
          total_pages: 0,
          offset: 0,
        }
      ),
      title: "Artifact Registry",
      page_data: {
        selected_link: :packages,
      },
    )
  end

  sig { params(repository: Repository, digest: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def fetch_attestations_by_digest(repository:, digest:)
    return [] if digest.blank?

    response = TrustMetadata.list_attestations_by_repository_and_subject_digest(repository, digest)

    return [] unless response.call_succeeded

    attestations = response.value&.attestations || []

    attestations.map do |attestation|
      cert_summary = attestation.certificate_summary

      # Extract workflow file from build_config_uri
      # Format: https://github.com/{owner}/{repo}/.github/workflows/{workflow_file}@refs/heads/{branch}
      workflow_file = nil
      if cert_summary&.build_config_uri.present?
        if match = cert_summary.build_config_uri.match(%r{\.github/workflows/(.+)})
          workflow_file = match[1]  # Includes everything after workflows/ (e.g., "build.yml@refs/heads/main")
        end
      end

      {
        id: attestation.id,
        predicateType: attestation.predicate_type,
        createdAt: attestation.created_at,
        runInvocationUri: cert_summary&.run_invocation_uri,
        workflowFile: workflow_file,
        repository: @artifact_metadata.repository.name,
      }
    end
  end

  def page_param
    value = params[:page]&.to_i
    return nil unless value && value > 0
    value
  end

  def per_page_param
    value = params[:per_page]&.to_i
    return nil unless value
    [[value, 1].max, 100].min
  end

  def deployment_page_param
    value = params[:deployment_page]&.to_i
    return nil unless value && value > 0
    value
  end

  def deployment_per_page_param
    value = params[:deployment_per_page]&.to_i
    return nil unless value
    [[value, 1].max, 100].min
  end

  memoize def parsed_query
    Search::ParsedQuery.new(params[:q].to_s, [:sort])
  end

  class ArtifactRegistryIndexRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "artifactRegistryIndexRoute"
    end

    sig { params(artifacts: T::Array[T::Hash[Symbol, T.untyped]], page_info: T::Hash[Symbol, T.untyped]).void }
    def initialize(artifacts:, page_info:)
      @artifacts = artifacts
      @page_info = page_info
    end

    def payload
      {
        artifacts: @artifacts,
        pageInfo: {
          hasNextPage: @page_info[:has_next_page],
          hasPreviousPage: @page_info[:has_previous_page],
          pageSize: @page_info[:page_size],
          currentPage: @page_info[:current_page],
          totalCount: @page_info[:total_count],
          totalPages: @page_info[:total_pages],
          offset: @page_info[:offset],
        },
      }
    end
  end

  class ArtifactRegistryShowRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "artifactRegistryShowRoute"
    end

    sig { params(artifact: T::Hash[Symbol, T.untyped], attestations: T::Array[T::Hash[Symbol, T.untyped]], deployments: T::Array[T::Hash[Symbol, T.untyped]], storage_record: T.nilable(T::Hash[Symbol, T.untyped]), deployment_page_info: T::Hash[Symbol, T.untyped]).void }
    def initialize(artifact:, attestations:, deployments:, storage_record:, deployment_page_info:)
      @artifact = artifact
      @attestations = attestations
      @deployments = deployments
      @storage_record = storage_record
      @deployment_page_info = deployment_page_info
    end

    def payload
      {
        artifact: @artifact,
        attestations: @attestations,
        deployments: @deployments,
        storageRecord: @storage_record,
        deploymentPageInfo: {
          page: @deployment_page_info[:page],
          perPage: @deployment_page_info[:per_page],
          totalCount: @deployment_page_info[:total_count],
          totalPages: @deployment_page_info[:total_pages],
          hasNextPage: @deployment_page_info[:has_next_page],
          hasPreviousPage: @deployment_page_info[:has_previous_page],
        },
      }
    end
  end
end
