# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseRepositoryInfo < Platform::Objects::Base
      description "A subset of repository information queryable from an enterprise."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.access_allowed?(:administer_business, resource: object.business,
          repo: nil, organization: nil,
          allow_integrations: false, allow_user_via_granular_actor: false)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.business.owner?(permission.viewer) || permission.viewer&.site_admin?
      end

      minimum_accepted_scopes ["admin:enterprise"]

      implements_node templates: [[:eri, :business_id, :id]], as: "ERI", ready_date: Platform::Helpers::GlobalId::COHORT_4 do |enterprise_repository_info|
        {
          prefix: :eri,
          business_id: enterprise_repository_info.business.id,
          id: enterprise_repository_info.id,
        }
      end

      field :name_with_owner, String, method: :async_name_with_owner, description: "The repository's name with owner.", null: false
      field :name, String, description: "The repository's name.", null: false
      field :is_private, Boolean, description: "Identifies if the repository is private or internal.", method: :private?, null: false

      def self.load_from_next_global_id(parsed_id)
        Promise.all([
          Objects::Repository.load_from_next_global_id(parsed_id),
          Loaders::ActiveRecord.load(::Business, parsed_id.parts[:business_id]),
        ]).then do |repo, business|
          if repo && business
            Models::EnterpriseRepositoryInfo.new(repo, business)
          else
            nil
          end
        end
      end
    end
  end
end
