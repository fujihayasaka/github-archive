# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Language < Platform::Objects::Base
      model_name "LanguageName"
      description "Represents a given language found in repositories."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, language)
        permission.access_allowed?(:public_site_information, resource: Platform::PublicResource.new, current_repo: nil, current_org: nil, allow_integrations: true, allow_user_via_granular_actor: true) # rubocop:disable GitHub/PublicResource
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # language is public
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:l, :language_id]], as: "LAN", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |language|
        { prefix: :l, language_id: language.id }
      end

      field :name, String, "The name of the current language.", null: false

      field :color, String, description: "The color defined for the current language.", null: true

      def color
        @object.language&.color
      end

      def self.load_from_next_global_id(parsed_id)
        load_from_global_id(parsed_id.id)
      end

      def self.load_from_global_id(id)
        Loaders::ActiveRecord.load(::LanguageName, id.to_i)
      end
    end
  end
end
