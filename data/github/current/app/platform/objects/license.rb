# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class License < Platform::Objects::Base
      description "A repository's open source license"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, license)
        permission.access_allowed?(:public_site_information, resource: Platform::PublicResource.new, current_repo: nil, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true) # rubocop:disable GitHub/PublicResource
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      implements_node templates: [[:l, :license_key]], as: "L", ready_date: Platform::Helpers::GlobalId::COHORT_5, uses_database_id: false do |license|
        { prefix: :l, license_key: license.key }
      end

      scopeless_tokens_as_minimum

      # Note: field descriptions can be found in https://git.io/vHY7z
      field :key, String, "The lowercased SPDX ID of the license", null: false
      field :name, String, "The license full name specified by <https://spdx.org/licenses>", null: false
      field :featured, Boolean, "Whether the license should be featured", method: :featured?, null: false
      field :hidden, Boolean, "Whether the license should be displayed in license pickers", method: :hidden?, null: false
      field :body, String, "The full text of the license", method: :body_as_string, null: false

      field :nickname, String, "Customary short name if applicable (e.g, GPLv3)", null: true
      field :description, String, "A human-readable description of the license", null: true
      field :implementation, String, "Instructions on how to implement the license", method: :how, null: true
      field :spdx_id, String, "Short identifier specified by <https://spdx.org/licenses>", null: true
      field :url, Scalars::URI, "URL to the license on <https://choosealicense.com>", null: true

      %i(conditions permissions limitations).each do |rule_group|
        field rule_group, [Objects::LicenseRule, null: true], "The #{rule_group} set by the license", null: false
        define_method(rule_group) do
          @object.rules[rule_group]
        end
      end

      field :pseudo_license, Boolean, "Whether the license is a pseudo-license placeholder (e.g., other, no-license)", method: :pseudo_license?, null: false

      def self.load_from_next_global_id(parsed_id)
        Promise.resolve(::License.find(parsed_id.parts[:license_key]))
      end

      def self.load_from_global_id(id)
        Promise.resolve(::License.find_by_id(id.to_i))
      end
    end
  end
end
