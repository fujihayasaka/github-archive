# typed: true
# frozen_string_literal: true

class ArtifactDeploymentRecord < ApplicationRecord::Domain::ArtifactRegistry
  RUNTIME_RISKS = [
    CRITICAL_RESOURCE = "critical-resource",
    INTERNET_EXPOSED = "internet-exposed",
    SENSITIVE_DATA = "sensitive-data",
    LATERAL_MOVEMENT = "lateral-movement"
  ].freeze

  belongs_to :artifact_metadata, inverse_of: :deployment_records

  validates :logical_environment, length: { maximum: 128 }
  validates :physical_environment, length: { maximum: 128 }
  validates :cluster, length: { maximum: 128 }
  validates :deployment_name, length: { maximum: 256 }
  validates :owner_id, presence: true

  scope :active, -> {
    where(deleted_at: nil)
  }

  after_commit :check_artifact_standalone, on: :update

  def check_artifact_standalone
    if T.unsafe(self).saved_change_to_artifact_metadata_id?
      check_previous_artifact_standalone
    elsif T.unsafe(self).saved_change_to_deleted_at?
      check_current_artifact_standalone
    end
  end

  # Called when a deployment record's artifact association
  # has been updated. It checks whether the previously associated artifact
  # has any remaining active record associations and soft deletes it if not.
  def check_previous_artifact_standalone
    return unless self.saved_change_to_artifact_metadata_id?

    old_metadata_id = self.artifact_metadata_id_before_last_save
    return unless old_metadata_id

    GitHub.logger.debug("Checking if artifact metadata #{old_metadata_id} is standalone after deployment record artifact association was updated",
      "previous_artifact_metadata_id" => old_metadata_id,
      "deployment_record_id" => self.id
    )
    old_metadata = ArtifactMetadata.find_by(id: old_metadata_id)
    old_metadata&.soft_delete_if_standalone
  end

  # Called when the deployment record's status has been updated
  # to 'deleted' or 'decommissioned' respectively. This indicates the records are marked
  # as deleted. This method checks if the currently associated artifact has any
  # remaining active record associations and soft deletes it if not.
  def check_current_artifact_standalone
    return unless self.saved_change_to_deleted_at?

    GitHub.logger.debug("Checking if artifact metadata #{self.artifact_metadata_id} is standalone after deployment record was marked as deleted",
      "artifact_metadata_id" => self.artifact_metadata_id,
      "deployment_record_id" => self.id
    )
    self.artifact_metadata&.soft_delete_if_standalone
  end

  # To avoid passing the application record around to different functions which can cause costly database lookups,
  # we can use the to_hash method to convert the record to a hash with all the necessary information for downstream
  # functions, including sending Hydro messages.
  def to_hash
    {
      id: id,
      digest: artifact_metadata&.digest,
      logical_environment: logical_environment,
      physical_environment: physical_environment,
      cluster: cluster,
      deployment_name: deployment_name,
      created_at: created_at,
      updated_at: updated_at,
      deleted_at: deleted_at,
      runtime_risks: runtime_risk_tag_values,
      custom_tags: custom_tags,
      org_id: artifact_metadata&.owner_id,
      repo_id: artifact_metadata&.repository_id,
      attestation_id: artifact_metadata&.attestation_id,
    }
  end

  sig { params(artifact_metadata_id: Integer, page: Integer, per_page: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def self.deployments_by_artifact_id_paginated(artifact_metadata_id:, page: 1, per_page: 20)
    offset = (page - 1) * per_page

    where(artifact_metadata_id: artifact_metadata_id)
      .order(Arel.sql("deleted_at IS NULL DESC, updated_at DESC"))
      .limit(per_page)
      .offset(offset)
      .map do |deployment|
        {
          deployment_name: deployment.deployment_name,
          logical_environment: deployment.logical_environment,
          physical_environment: deployment.physical_environment,
          cluster: deployment.cluster,
          created_at: deployment.created_at,
          updated_at: deployment.updated_at,
          deleted_at: deployment.deleted_at,
          runtime_risks: deployment.runtime_risk_tag_values
        }
      end
  end

  sig { params(artifact_metadata_id: Integer).returns(Integer) }
  def self.deployment_count_by_artifact_id(artifact_metadata_id:)
    where(artifact_metadata_id: artifact_metadata_id).count
  end

  def deployed?
    deleted_at.nil?
  end

  def decommissioned?
    deleted_at.present?
  end

  def decommission(time = Time.now)
    self.update!(deleted_at: time)
  end

  # update an existing deployment record with new artifact association, tags, and runtime risks.
  def update_event(artifact, tags, runtime_risks)
    record_updated = false
    if artifact_metadata != artifact
      update(artifact_metadata: artifact)
      record_updated = true
    end
    update_all_tags(tags, runtime_risks)
    # Only update the updated_at timestamp explicitly if the record wasn't already updated by the artifact association change,
    # as updating the updated_at time stamp will already be handled by the callback triggered by the artifact association change
    # and calling it again here can interfere with the callback logic
    if !record_updated && (tags.present? || runtime_risks.present?)
      update(updated_at: Time.now)
    end
  end

  has_many :deployment_record_tags,
    class_name: "ArtifactDeploymentRecordTag",
    foreign_key: :deployment_record_id,
    inverse_of: :deployment_record,
    dependent: :destroy

  # currently we only allow up to 5 custom tags and 4 runtime risk tags
  validate :validate_tag_limits

  sig { params(deploy_params: T::Hash[Symbol, T.nilable(String)], github_repo_id: Integer, deployed_status_only: T.nilable(T::Boolean)).returns(T.nilable(ArtifactDeploymentRecord)) }
  def self.record_by_deploy_params_and_repo(deploy_params, github_repo_id, deployed_status_only: false)
    query = joins(:artifact_metadata)
      .where(logical_environment: deploy_params[:logical_environment])
      .where(physical_environment: deploy_params[:physical_environment])
      .where(cluster: deploy_params[:cluster])
      .where(deployment_name: deploy_params[:deployment_name])
      .where(artifact_metadata: { repository_id: github_repo_id })

    query = query.where(deleted_at: nil) if deployed_status_only
    query.first
  end

  sig { params(owner_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def self.repository_ids_for_owners(owner_ids)
    where(owner_id: owner_ids)
      .where(deleted_at: nil)
      .joins(:artifact_metadata)
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  def self.records_with_cluster(logical_env, physical_env, cluster_name, owner_id)
    where(logical_environment: logical_env, physical_environment: physical_env, cluster: cluster_name, owner_id: owner_id, deleted_at: nil)
  end

  sig { params(owner_ids: T::Array[Integer], runtime_risks: T::Array[String]).returns(T::Array[Integer]) }
  def self.repository_ids_for_owners_and_runtime_risks(owner_ids:, runtime_risks:)
    return [] if runtime_risks.empty?

    where(owner_id: owner_ids)
      .where(deleted_at: nil)
      .joins(:artifact_metadata)
      .joins(:deployment_record_tags)
      .where(deployment_record_tags: { tag_name: "runtime-risk", tag_value: runtime_risks })
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  # Only for automatic active record creation
  def custom_tags=(tags)
    return unless tags.present?

    tag_params = convert_custom_tags_to_table_format(tags)
    deployment_record_tags.build(tag_params)
  end

  def create_custom_tags(tags)
    return unless tags.present?

    tag_params = convert_custom_tags_to_table_format(tags)
    deployment_record_tags.create(tag_params)
  end

  def update_custom_tags(tags)
    return unless tags.present?

    tag_params = convert_custom_tags_to_table_format(tags)
    deployment_record_tags.where.not(tag_name: "runtime-risk").destroy_all
    deployment_record_tags.create(tag_params)
  end

  sig { params(custom_tags: T.nilable(T::Hash[String, String]), runtime_risks: T.nilable(T::Array[String])).void }
  def update_all_tags(custom_tags, runtime_risks)
    return if custom_tags.nil? && runtime_risks.nil?

    custom_tag_params = convert_custom_tags_to_table_format(custom_tags)
    runtime_risk_tag_params = convert_runtime_risks_to_table_format(runtime_risks)
    all_tag_params = custom_tag_params + runtime_risk_tag_params

    deployment_record_tags.destroy_all
    deployment_record_tags.create(all_tag_params)
  end

  # Only for automatic active record creation
  def runtime_risk_tags=(risks)
    return unless risks.present?

    table_runtime_risk_params = risks.map do |risk|
      { tag_name: "runtime-risk", tag_value: risk }
    end

    deployment_record_tags.build(table_runtime_risk_params)
  end

  def update_runtime_risk_tags(risks)
    return unless risks.present?

    table_runtime_risk_params = risks.map do |risk|
      { tag_name: "runtime-risk", tag_value: risk }
    end

    deployment_record_tags.where(tag_name: "runtime-risk").destroy_all
    deployment_record_tags.create(table_runtime_risk_params)
  end

  # Simplified version to match the input options above
  # If you want the full database values, use deployment_record_tags
  def custom_tags
    tags = deployment_record_tags.where.not(tag_name: "runtime-risk").pluck(:tag_name, :tag_value)
    tags.to_h
  end

  def runtime_risk_tag_values
    deployment_record_tags.where(tag_name: "runtime-risk").pluck(:tag_value)
  end

  private

  # validate runtime-risk and custom tag limits
  def validate_tag_limits
    tags_array = deployment_record_tags.to_a
    custom_tags_count = tags_array.count { |tag| tag.tag_name != "runtime-risk" }
    runtime_risk_tags_count = tags_array.count { |tag| tag.tag_name == "runtime-risk" }

    if custom_tags_count > 5
      errors.add(:deployment_record_tags, "Exceeded maximum number of custom tags allowed (5)")
    end

    if runtime_risk_tags_count > 4
      errors.add(:deployment_record_tags, "Exceeded maximum number of runtime risk tags allowed (4)")
    end
  end

  sig { params(tags: T.nilable(T::Hash[String, String])).returns(T::Array[T::Hash[Symbol, String]]) }
  def convert_custom_tags_to_table_format(tags)
    return [] if tags.nil?

    tags.map do |k, v|
      { tag_name: k, tag_value: v }
    end
  end

  sig { params(risks: T.nilable(T::Array[String])).returns(T::Array[T::Hash[Symbol, String]]) }
  def convert_runtime_risks_to_table_format(risks)
    return [] if risks.nil?

    risks.map do |risk|
      { tag_name: "runtime-risk", tag_value: risk }
    end
  end
end
