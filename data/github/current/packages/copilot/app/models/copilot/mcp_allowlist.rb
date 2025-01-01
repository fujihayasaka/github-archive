# typed: strict
# frozen_string_literal: true

module Copilot
  class McpAllowlist < ApplicationRecord::Copilot
    self.table_name = "copilot_mcp_allowlists"
    self.strict_loading_by_default = true

    belongs_to :entity, polymorphic: true, strict_loading: false
    # rubocop:todo Rails/InverseOf
    belongs_to :updated_by, class_name: "::User", foreign_key: "updated_by_id", strict_loading: false

    validates :entity, presence: true
    validates :entity_id, presence: true
    validates :entity_type, inclusion: { in: %w[Business Organization] }
    validate :ensure_valid_url

    scope :for_business, ->(entities) { where(entity_id: entities.respond_to?(:pluck) ? entities.pluck(:id) : entities.id, entity_type: "Business") }
    scope :for_organization, ->(entities) { where(entity_id: entities.respond_to?(:pluck) ? entities.pluck(:id) : entities.id, entity_type: "Organization") }

    enum :registry_access, {
      allow_all: 0,
      allow_with_warning: 1,
      registry_only: 2
    }, prefix: true

    sig { void }
    def ensure_valid_url
      if allowlist_url.present? && !(allowlist_url =~ URI::RFC2396_PARSER.regexp[:ABS_URI])
        errors.add(:allowlist_url, "invalid URL format")
      end
    end

    sig { returns(T::Hash[Symbol, T.any(String, Integer, DateTime)]) }
    def to_json_hash
      {
        id: id,
        allowlist_url: allowlist_url,
        entity_id: entity_id,
        entity_type: entity_type,
        updated_by_id: updated_by_id,
        created_at: created_at,
        updated_at: updated_at
      }
    end

    # Alias for allowlist_url until we update the column name in the database
    # The appropriate name for the column is `registry_url`, NOT `allowlist_url`
    sig { returns(T.nilable(String)) }
    def registry_url
      allowlist_url
    end

    sig { params(value: T.nilable(String)).void }
    def registry_url=(value)
      self.allowlist_url = value
    end
  end
end
