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

  validates :logical_environment, length: { maximum: 64 }
  validates :physical_environment, length: { maximum: 64 }
  validates :cluster, length: { maximum: 64 }
  validates :deployment_name, length: { maximum: 128 }
  validates :owner_id, presence: true

  scope :active, -> {
    where(deleted_at: nil)
  }

  sig { params(artifact_metadata_id: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def self.deployments_by_artifact_id(artifact_metadata_id)
    where(artifact_metadata_id: artifact_metadata_id)
      .order(:created_at)
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

  def deployed?
    deleted_at.nil?
  end

  def decommissioned?
    deleted_at.present?
  end

  def decommission(time = Time.now)
    self.update!(deleted_at: time)
  end

  has_many :deployment_record_tags,
    class_name: "ArtifactDeploymentRecordTag",
    foreign_key: :deployment_record_id,
    inverse_of: :deployment_record,
    dependent: :destroy

  # currently we only allow up to 5 custom tags and 4 runtime risk tags
  validate :validate_tag_limits

  sig { params(deploy_params: T::Hash[Symbol, T.nilable(String)], github_repo_id: Integer).returns(T.nilable(ArtifactDeploymentRecord)) }
  def self.record_by_deploy_params_and_repo(deploy_params, github_repo_id)
    joins(:artifact_metadata)
      .where(logical_environment: deploy_params[:logical_environment])
      .where(physical_environment: deploy_params[:physical_environment])
      .where(cluster: deploy_params[:cluster])
      .where(deployment_name: deploy_params[:deployment_name])
      .where(artifact_metadata: { repository_id: github_repo_id })
      .first
  end

  sig { params(deploy_params: T::Hash[Symbol, T.nilable(String)], github_repo_id: Integer).returns(T.nilable(ArtifactDeploymentRecord)) }
  def self.deployed_record_by_deploy_params_and_repo(deploy_params, github_repo_id)
    joins(:artifact_metadata)
      .where(logical_environment: deploy_params[:logical_environment])
      .where(physical_environment: deploy_params[:physical_environment])
      .where(cluster: deploy_params[:cluster])
      .where(deployment_name: deploy_params[:deployment_name])
      .where(deleted_at: nil)
      .where(artifact_metadata: { repository_id: github_repo_id })
      .first
  end

  sig { params(owner_id: Integer).returns(T::Array[Integer]) }
  def self.repository_ids_for_owner(owner_id)
    where(owner_id: owner_id)
      .joins(:artifact_metadata)
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  sig { params(owner_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def self.repository_ids_for_owners(owner_ids)
    where(owner_id: owner_ids)
      .joins(:artifact_metadata)
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  sig { params(owner_id: Integer).returns(T::Array[Integer]) }
  def self.repository_ids_for_owner_and_any_runtime_risk(owner_id)
    where(owner_id: owner_id)
      .joins(:deployment_record_tags)
      .where(deployment_record_tags: { tag_name: "runtime-risk" })
      .joins(:artifact_metadata)
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  sig { params(owner_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def self.repository_ids_for_owners_and_any_runtime_risk(owner_ids)
    where(owner_id: owner_ids)
      .joins(:deployment_record_tags)
      .where(deployment_record_tags: { tag_name: "runtime-risk" })
      .joins(:artifact_metadata)
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  def self.records_with_cluster(logical_env, physical_env, cluster_name, owner_id)
    where(logical_environment: logical_env, physical_environment: physical_env, cluster: cluster_name, owner_id: owner_id)
  end

  sig { params(owner_id: Integer, runtime_risks: T::Array[String]).returns(T::Array[Integer]) }
  def self.repository_ids_for_owner_and_runtime_risks(owner_id:, runtime_risks:)
    return [] if runtime_risks.empty?

    where(owner_id: owner_id)
      .joins(:artifact_metadata)
      .joins(:deployment_record_tags)
      .where(deployment_record_tags: { tag_name: "runtime-risk", tag_value: runtime_risks })
      .distinct
      .pluck("artifact_metadata.repository_id")
  end

  sig { params(owner_ids: T::Array[Integer], runtime_risks: T::Array[String]).returns(T::Array[Integer]) }
  def self.repository_ids_for_owners_and_runtime_risks(owner_ids:, runtime_risks:)
    return [] if runtime_risks.empty?

    where(owner_id: owner_ids)
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
