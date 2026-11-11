# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Mannequin < Platform::Objects::Base
      docs_category :migrations
      description "A placeholder user for attribution of imported data on GitHub."

      key fields: :database_id

      def self.resolve_reference(reference, context)
        database_id = reference.is_a?(Hash) && reference[:database_id].to_i
        if database_id && database_id > 0
          Platform::Loaders::ActiveRecord.load(::Mannequin, database_id, security_violation_behaviour: :nil)
        else
          Platform::Interfaces::Node.resolve_reference_by_node_id(self, reference, context)
        end
      end

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

      def url
        "#{GitHub.url}/#{GitHub.ghost_user_login}"
      end

      # WARNING: this field is defined as Int in the GraphQL schema, but the underlying DB ID is BigInt
      # please consider deprecating it in favour of full_database_id_field
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

      field :avatar_url, Scalars::URI, description: "A URL pointing to the GitHub App's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(size: nil)
        @object.async_primary_avatar.then do
          @object.primary_avatar_url(size)
        end
      end
    end
  end
end
