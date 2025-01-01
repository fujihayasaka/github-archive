# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryProjectsEnabledCheck < Platform::Loader
      def self.load(repository_id)
        self.for.load(repository_id)
      end

      def fetch(repository_ids)
        base_scope = ::Configuration::Entry.named(::Configurable::DisableRepositoryProjects::KEY)
          .with_true_value

        organization_for_repository_id = Repository.where({
          id: repository_ids,
        }).org_owned.pluck(:id, :owner_id).to_h
        organization_ids = organization_for_repository_id.values.uniq

        disabled_organization_ids = Set.new
        disabled_repository_ids = Set.new

        scope = base_scope.targeting_repository_ids(repository_ids)

        if organization_ids.any?
          scope = scope.or(base_scope.targeting_user_ids(organization_for_repository_id.values.uniq))
        end

        scope.pluck(:target_type, :target_id).each do |target_type, target_id|
          case target_type
          when "Repository"
            disabled_repository_ids << target_id
          when "User"
            disabled_organization_ids << target_id
          end
        end

        repository_ids.each_with_object({}) do |id, result|
          if disabled_repository_ids.include?(id)
            result[id] = false
          else
            organization_id = organization_for_repository_id[id]
            if organization_id && disabled_organization_ids.include?(organization_id)
              result[id] = false
            else
              result[id] = true
            end
          end
        end
      end
    end
  end
end
