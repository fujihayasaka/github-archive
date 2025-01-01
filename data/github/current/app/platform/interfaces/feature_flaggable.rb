# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module FeatureFlaggable
      include Platform::Interfaces::Base
      description "An object for which features can be enabled or disabled"
      visibility :internal

      CUSTOM_CHECK_ENABLED_FEATURES = %w(extract_checklists)

      # use this with field aliasing to avoid inclusion testing to see if a particular feature is enabled
      field :is_feature_enabled, Boolean, visibility: :internal, description: "Check if the requested feature is enabled", null: false do
        argument :name, String, "The feature flag which we are checking for this object.", required: true
        argument :custom_feature_check, Boolean, "If true, call name_enabled? method on the object for feature flag check.", default_value: false, required: false
      end

      def is_feature_enabled(name:, custom_feature_check: false)
        GitHub.dogstats.increment("feature_flaggable.is_feature_enabled", tags: ["feature:#{name}"])
        return GitHub.flipper[name].enabled?(@object) unless custom_feature_check

        return false unless CUSTOM_CHECK_ENABLED_FEATURES.include?(name) && @object.respond_to?("#{name}_enabled?")

        @object.send("#{name}_enabled?")
      end

      # use this with field aliasing to avoid inclusion testing to see if a particular beta feature is enabled
      field :is_beta_feature_enabled, Boolean, visibility: :internal, description: "Check if the requested beta feature is enabled", null: false do
        argument :name, String, "The beta feature which we are checking for this object.", required: true
      end

      def is_beta_feature_enabled(name:)
        @object &&
          @object.respond_to?(:feature_preview_enabled?) &&
          @object.feature_preview_enabled?(name)
      end
    end
  end
end
