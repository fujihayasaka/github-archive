# typed: strict
# frozen_string_literal: true

module Copilot
  class IntegrationAgentSource < ApplicationRecord::Domain::Copilot
    self.table_name = "integration_agent_sources"
    self.strict_loading_by_default = true

    ENGINE_YAML_PATH = "engine.yaml"

    belongs_to :integration, strict_loading: false, inverse_of: :agent_source, optional: false

    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain foreign_key: :repository_id, strict_loading: false

    validates :integration_id, uniqueness: true
    validates :repository_id, presence: true
    validates :commit_oid, presence: true
    validate  :validate_repository_and_commit_oid

    serialize :model_vendors, type: Array

    after_save :sync_model_vendors_from_engine_yaml

    private

    sig { void }
    def validate_repository_and_commit_oid
      repo = repository
      return if repo.nil?

      # Validate repository is public (not private or internal)
      unless repo.public?
        errors.add(:repository_id, "must be a public repository")
        return
      end

      # Validate commit_oid exists in repository
      return if commit_oid.blank?

      commit = T.unsafe(repo).commits.find_for_sha(commit_oid)
      if commit
        self.commit_oid = commit.oid
      else
        errors.add(:commit_oid, "does not exist in the repository")
      end
    rescue GitRPC::ObjectMissing, RepositoryObjectsCollection::InvalidObjectId
      errors.add(:commit_oid, "does not exist in the repository")
    end

    sig { void }
    def sync_model_vendors_from_engine_yaml
      return unless FeatureFlag.vexi.enabled?(:copilot_engine_sdk_model_selection, default: false)
      return unless previously_new_record? || saved_change_to_commit_oid?
      return unless self.class.column_names.include?("model_vendors")

      repo = repository
      return if repo.nil? || commit_oid.blank?

      vendors = fetch_vendors_from_engine_yaml(repo)
      stored = vendors.blank? ? nil : vendors
      current = model_vendors
      update_column(:model_vendors, stored) if current != stored
    rescue => e
      GitHub.logger.warn(
        "Failed to sync model_vendors from engine.yaml: #{e.message}",
        "code.namespace": "Copilot::IntegrationAgentSource",
        "code.function": "sync_model_vendors_from_engine_yaml",
        "gh.integration.id": integration_id,
      )
    end

    sig { params(repo: ::Repositories::IRepository).returns(T::Array[String]) }
    def fetch_vendors_from_engine_yaml(repo)
      metadata = ::Repositories.domain.contents.metadata_by_ref_and_path(
        repository: repo,
        ref: commit_oid,
        path: ENGINE_YAML_PATH,
      )

      return [] if metadata.object_not_found?

      blob = ::Repositories.domain.contents.blob_by_path_and_metadata(
        repository: repo,
        path: ENGINE_YAML_PATH,
        metadata: metadata,
      )

      return [] if blob.nil? || blob.contents.blank?

      parsed = YAML.safe_load(blob.contents)
      return [] unless parsed.is_a?(Hash)

      # Support both `vendors: [...]` (array) and `vendor: "..."` (single, backward-compat)
      if parsed["vendors"].is_a?(Array)
        parsed["vendors"].map(&:to_s).select(&:present?)
      elsif parsed["vendor"].present?
        [parsed["vendor"].to_s]
      else
        []
      end
    rescue Psych::SyntaxError
      []
    end
  end
end
