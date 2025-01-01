# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Actor < Resolvers::Base
      type Interfaces::Actor, null: true

      def async_actor
        raise NotImplementedError, "Should return a promise to the actor, eg `object.async_creator` or `object.async_user`" # rubocop:disable GitHub/UsePlatformErrors
      end

      class << self
        attr_accessor :association_name
      end

      # Create a subclass which uses `association_name` to find the actor
      def self.create(association_name)
        Class.new(self) do
          graphql_name "Actor"
          self.association_name = association_name
        end
      end

      def resolve
        async_actor.then do |user|
          next unless user
          next if user.is_a?(Organization)

          business_promise = if context[:viewer]&.feature_enabled?(:graphql_preload_business_user_accounts)
            # preload business_user_accounts for permission attributes, prevents n+1 for .authorized? checks
            user.async_business_user_accounts
          else
            Promise.resolve
          end

          business_promise.then do
            context[:permission].typed_can_see?("User", user).then do |can_read|
              if can_read && !user.hide_from_user?(context[:viewer])
                user
              end
            end
          end
        end
      end
    end
  end
end
