# typed: strict
# frozen_string_literal: true

class ClusterDeploymentManager
  class DeploymentError < T::Struct
    prop :name, String
    prop :digest, String
    prop :deployment_name, String
    prop :version, T.nilable(String)
    prop :status, String
    prop :github_repository, T.nilable(String)
    prop :tags, T::Hash[T.untyped, T.untyped]
    prop :runtime_risks, T::Array[String]
  end

  class ErrorEntry < T::Struct
    prop :cause, String
    prop :deployment, DeploymentError
  end

  class CategorizedDeploymentChanges < T::Struct
    prop :to_create, T::Array[DeploymentTemplate]
    prop :to_delete, T::Array[ArtifactDeploymentRecord]
    prop :to_update, T::Array[DeploymentTemplate]
  end

  class ConflictInfo < T::Struct
    prop :proposed_template, DeploymentTemplate
    prop :conflicting_records, T::Array[ArtifactDeploymentRecord]
  end

  sig { returns(String) }
  attr_reader :cluster

  sig { returns(T::Array[ArtifactDeploymentRecord]) }
  attr_reader :authorized_records

  sig { returns(T::Array[DeploymentTemplate]) }
  attr_reader :authorized_templates

  sig { returns(T::Array[ArtifactDeploymentRecord]) }
  attr_reader :unauthorized_records

  sig { returns(T::Array[DeploymentTemplate]) }
  attr_reader :unauthorized_templates

  sig { returns(T::Array[ArtifactDeploymentRecord]) }
  attr_reader :not_found_records

  sig { returns(T::Array[DeploymentTemplate]) }
  attr_reader :not_found_templates

  sig { returns(T::Array[ConflictInfo]) }
  attr_reader :conflicted_deployments

  sig { params(cluster: String, authorization_result: Api::App::ArtifactMetadataPermissionsHelper::AuthorizationResult).void }
  def initialize(cluster, authorization_result)
    @cluster = T.let(cluster, String)
    @authorized_records = T.let(authorization_result.authorized.current_records, T::Array[ArtifactDeploymentRecord])
    @authorized_templates = T.let(authorization_result.authorized.proposed_records, T::Array[DeploymentTemplate])
    @unauthorized_records = T.let(authorization_result.unauthorized.current_records, T::Array[ArtifactDeploymentRecord])
    @unauthorized_templates = T.let(authorization_result.unauthorized.proposed_records, T::Array[DeploymentTemplate])
    @not_found_records = T.let(authorization_result.not_found.current_records, T::Array[ArtifactDeploymentRecord])
    @not_found_templates = T.let(authorization_result.not_found.proposed_records, T::Array[DeploymentTemplate])
    @conflicted_deployments = T.let([], T::Array[ConflictInfo])
  end

  sig { returns(T::Array[ConflictInfo]) }
  def detect_deployment_name_conflicts
    conflicts = []

    # Build a map of all inaccessible records by deployment_name
    inaccessible_records = @unauthorized_records + @not_found_records
    inaccessible_by_name = inaccessible_records.group_by(&:deployment_name)

    # Find templates attempting to update inaccessible records
    conflicting_deployment_names = Set.new
    @authorized_templates.each do |template|
      conflicting_records = inaccessible_by_name[template.deployment_name]
      if conflicting_records&.any?
        conflicts << ConflictInfo.new(
          proposed_template: template,
          conflicting_records: conflicting_records
        )
        conflicting_deployment_names << template.deployment_name
      end
    end

    # Remove conflicting templates from authorized_templates so they won't be processed for updates
    @authorized_templates = @authorized_templates.reject { |t| conflicting_deployment_names.include?(t.deployment_name) }

    @conflicted_deployments = conflicts
    conflicts
  end

  sig { returns(CategorizedDeploymentChanges) }
  def categorize_cluster_deployment_changes
    # Create a hash of current records for easy lookup by deployment_name
    # This will be used to determine which records need to be updated, created, or deleted
    current_records_by_deployment_name = @authorized_records.each_with_object({}) do |record, hash|
      hash[record.deployment_name] = record
    end

    if @authorized_templates.blank?
      # If there are no incoming deployment templates, then all existing records should be deleted
      return CategorizedDeploymentChanges.new(to_create: [], to_delete: @authorized_records, to_update: [])
    end

    to_update = []
    to_create = []

    @authorized_templates.each do |template|
      # If a deployment template does not have valid artifact linkage, skip it as it should be processed by the endpoint.
      next if !template.has_valid_artifact_linkage?

      deployment_name = template.deployment_name

      # Because we have already looked up existing records by cluster, logical_environment, and physical_environment,
      # we only need to check whether the deployment_name of a new proposed record matches an existing record in the hash
      existing_record = current_records_by_deployment_name[deployment_name]

      if existing_record
        to_update << template
        # delete the hash entry as we have already claimed it for update operations
        current_records_by_deployment_name.delete(deployment_name)
      else
        to_create << template
      end
    end

    # Any records remaining in the hash were not in the incoming deployments, so they should be deleted
    to_delete = current_records_by_deployment_name.values

    GitHub.logger.debug("Cluster deployment record changes categorized for cluster #{@cluster}: to_create=#{to_create.size}, to_update=#{to_update.size}, to_delete=#{to_delete.size}", "gh.cluster" => @cluster)
    CategorizedDeploymentChanges.new(to_create: to_create, to_delete: to_delete, to_update: to_update)
  end

  sig { returns T::Array[ErrorEntry] }
  def build_error_response
    errors = []

    # Add unauthorized errors
    @unauthorized_templates.each do |deployment|
      error = ErrorEntry.new(
        cause: "unauthorized",
        deployment: DeploymentError.new(
          name: deployment.artifact_template.name,
          digest: deployment.artifact_template.digest,
          deployment_name: deployment.deployment_name,
          version: deployment.artifact_template.version,
          status: deployment.status,
          github_repository: deployment.github_repository,
          tags: deployment.tags,
          runtime_risks: deployment.runtime_risks
        )
      )
      errors << error
    end

    # Add not_found errors
    @not_found_templates.each do |deployment|
      error = ErrorEntry.new(
        cause: "not_found",
        deployment: DeploymentError.new(
          name: deployment.artifact_template.name,
          digest: deployment.artifact_template.digest,
          deployment_name: deployment.deployment_name,
          version: deployment.artifact_template.version,
          status: deployment.status,
          github_repository: deployment.github_repository,
          tags: deployment.tags,
          runtime_risks: deployment.runtime_risks
        )
      )
      errors << error
    end

    # Add deployment name conflicts as "unauthorized" errors
    # When a user loses access to the original repo but tries to create the same deployment
    # pointing to a different repo, we treat both as unauthorized
    @conflicted_deployments.each do |conflict|
      records = conflict.conflicting_records
      conflict_errors = records.each_with_object([]) do |record, conflict_list|
        artifact_metadata = T.must(record.artifact_metadata)
        repo = T.must(artifact_metadata.repository)
        error = ErrorEntry.new(
          cause: "unauthorized",
          deployment: DeploymentError.new(
            name: artifact_metadata.name,
            digest: artifact_metadata.digest,
            deployment_name: record.deployment_name,
            version: artifact_metadata.version,
            status: artifact_metadata.status,
            github_repository: repo.name,
            tags: record.custom_tags,
            runtime_risks: record.runtime_risk_tag_values
          )
        )
        conflict_list << error
      end

      errors.concat(conflict_errors)
    end

    errors
  end
end
