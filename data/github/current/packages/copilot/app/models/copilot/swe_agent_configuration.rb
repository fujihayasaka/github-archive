# typed: true
# frozen_string_literal: true

module Copilot
  class SweAgentConfiguration < ApplicationRecord::Copilot

    include GitHub::Memoizer

    self.strict_loading_by_default = true
    self.table_name = "copilot_swe_agent_configuration"

    DOC_CHAR_LIMIT_IN_DB = 65_535
    DOC_CHAR_LIMIT_DESERIALIZED = 1_048_576

    belongs_to :resource, polymorphic: true, strict_loading: false
    # rubocop:todo Rails/InverseOf
    belongs_to :updated_by, class_name: "::User", foreign_key: "updated_by_id", strict_loading: false

    attribute :mcp_configuration, CompressedString.new(self.name, "mcp_configuration")

    validates :resource, presence: true
    validates :resource_type, inclusion: { in: %w[Repository] }

    validate :mcp_configuration_serialized_length
    validate :validate_deserialized_mcp_configuration

    #  TODO add instrumentation
    #  after_commit :instrument_update, on: [:create, :update]

    scope :for_repository, ->(entities) { where(resource_id: entities.respond_to?(:pluck) ? entities.pluck(:id) : entities.id, resource_type: "Repository") }

    def mcp_configuration_serialized_length
      raw_value = self.class.type_for_attribute(:mcp_configuration).serialize(read_attribute(:mcp_configuration))
      if raw_value.to_s.bytesize > DOC_CHAR_LIMIT_IN_DB
        errors.add(:mcp_configuration, "is too long after serialization (max is #{DOC_CHAR_LIMIT_IN_DB} bytes)")
      end
    end

    # We do this validation mostly to prevent zipbomb-like behavior, and to make sure we have a CYA around
    # payloads we are TWIRPing.
    def validate_deserialized_mcp_configuration
      deserialized_value = self.class.type_for_attribute(:mcp_configuration).cast(read_attribute(:mcp_configuration))

      return if deserialized_value.blank?

      if deserialized_value.bytesize > DOC_CHAR_LIMIT_DESERIALIZED
        errors.add(:mcp_configuration, "is too large when decompressed (max is #{DOC_CHAR_LIMIT_DESERIALIZED} bytes)")
      end
    end

    private

    sig { void }
    def instrument_update
      # TODO
      # Copilot::Instrumenter.instrument_content_exclusion_changed(resource, updated_by, document)
    end
  end
end
