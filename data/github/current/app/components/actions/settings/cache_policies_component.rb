# typed: true
# frozen_string_literal: true

module Actions
  module Settings

    class CachePoliciesComponent < ApplicationComponent
      DEFAULT = "Default".freeze
      MAXIMUM = "Maximum".freeze

      def initialize(entity:)
        @entity = entity
        @relevant_entities = ActionsPolicyHelper.get_relevant_entities(entity: @entity)
      end

      def render?
        return false if !FeatureFlag.vexi.enabled?("actions_cache_use_storage_and_retention_policies", Billing::EntityResolver.billing_owner(@entity), default: false)

        ActionsPolicyHelper.entity_can_use_cache_policies?(@entity)
      end

      def description
        return "Choose the repository settings for cache." if @entity.is_a?(Repository)
        return "Choose the settings for caches. Repositories can set their own limits, but cannot exceed the maximum set here." if @entity.is_a?(Organization)
        "Set the policy maximums for cache. Repositories and organizations can set their own limits, but cannot exceed the maximum set here."
      end
    end
  end
end
