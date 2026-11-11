# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class OrganizationProjectsEnabledCheck < Platform::Loader
      def self.load(organization_id)
        self.for.load(organization_id)
      end

      def fetch(organization_ids)
        disabled_organization_ids = ::Configuration::Entry.targeting_user_ids(organization_ids)
          .named(::Configurable::DisableOrganizationProjects::KEY)
          .with_true_value
          .pluck(:target_id)

        disabled_organization_ids.each_with_object(Hash.new(true)) do |id, result|
          result[id] = false
        end
      end
    end
  end
end
