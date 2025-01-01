# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class ProjectDeprecation
      def self.raise_if_deprecation_enabled(viewer)
        return if GitHub.projects_classic_creation_enabled?

        return if viewer.feature_enabled?(:memex_bypass_projects_classic_deprecation_rules)

        raise Platform::Errors::NotFound, "Projects (classic) creation is disabled for this resource"
      end
    end
  end
end
