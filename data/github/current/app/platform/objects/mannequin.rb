# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Mannequin < Platform::Objects::Base
      description "A placeholder user for attribution of imported data on GitHub."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, mannequin)
        permission.typed_can_access?("User", mannequin)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        !object.hide_from_user?(permission.viewer)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:m, :mannequin_id]], as: "M", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |mannequin|
        { prefix: :m, mannequin_id:  mannequin.id }
      end

      implements Interfaces::Actor

      implements Interfaces::UniformResourceLocatable

      database_id_field

      created_at_field
      updated_at_field

      field :email, String, "The mannequin's email on the source instance.", null: true
      field :name, String, "The display name of the imported mannequin.", null: true
      field :claimant, Objects::User, description: "The user that has claimed the data attributed to this mannequin.", null: true

      def claimant
        Platform::Loaders::ActiveRecordAssociation.load(@object, :claimant).then do |_claimant|
          @object.claimant
        end
      end

      def name
        @object.async_profile.then do |_profile|
          @object.name
        end
      end


      field :avatar_url, Scalars::URI, description: "A URL pointing to the GitHub App's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(size: nil)
        if context[:viewer]&.feature_flag_enabled_or_raise?(:gql_mannequin_avatar_url) || ::FeatureFlag.vexi.enabled_or_raise?(:gql_mannequin_avatar_url) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage, GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          @object.async_primary_avatar.then do
            @object.primary_avatar_url(size)
          end
        else
          ::User.ghost.primary_avatar_url(size)
        end
      end
    end
  end
end
