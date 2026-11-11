# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class Reactor < Edges::Base
      description "Represents an author of a reaction."

      def self.authorized?(edge, context)
        Platform::Loaders::ActiveRecord.load(::User, edge.node).then do |user|
          self.node_type.authorized?(user, context)
        end
      end

      field :node, Unions::Reactor, description: "The author of the reaction.", null: false

      def node
        Platform::Loaders::ActiveRecord.load(::User, object.node).then do |user|
          user ||= ::User.ghost
        end
      end

      field :reacted_at, Scalars::DateTime, description: "The moment when the user made the reaction.", null: false

      def reacted_at
        reaction_group = @object.parent
        user_id = @object.node
        reaction_group.subject.reactions.find_by(user_id: user_id, content: reaction_group.emotion.content).created_at
      end

      field :preferred_emoji_skin_tone, Integer, description: "The reactor's preferred emoji skin tone preference. Returns 0 for non-human reactors.", null: false, visibility: :internal

      def preferred_emoji_skin_tone
        return 0 unless FeatureFlag.vexi.enabled?("issues_user_setting_preference", context[:viewer], default: false)

        Platform::Loaders::ActiveRecord.load(::User, object.node).then do |user|
          user ||= ::User.ghost
          if ::FeatureFlag.vexi.enabled?(:fix_bad_return_platform_reactor, default: false)
            next 0 unless user.user?
          else
            return 0 unless user.user? # rubocop:disable GitHub/DontReturnInsidePromiseThen
          end

          user.profile_settings.async_preferred_emoji_skin_tone
        end
      end
    end
  end
end
