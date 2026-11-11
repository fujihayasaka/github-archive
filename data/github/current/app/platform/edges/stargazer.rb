# typed: false
# frozen_string_literal: true

module Platform
  module Edges
    class Stargazer < Edges::Base
      description "Represents a user that's starred a repository."

      def self.authorized?(object, context)
        star = object.node
        if star.is_a?(::GistStar)
          # There is no `GistStar` type, but we have special GistStar-related
          # authorization hooks, so we'll have to put them here.
          context[:permission].spam_check(object).then do |spam_ok|
            if spam_ok
              star.async_gist.then do |gist|
                gist.async_user.then do |owner|
                  org = owner.is_a?(Organization) ? owner : nil
                  context[:permission].access_allowed?(:get_gist_star, resource: gist, current_org: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: true)
                end
              end
            else
              false
            end
          end
        elsif star.is_a?(::Star)
          # Show this edge to anyone who can see the thing that was starred
          star.async_starrable.then do |starrable|
            starrable_graphql_type = Platform::Objects.const_get(star.starrable_type)
            starrable_graphql_type.authorized?(starrable, context)
          end
        else
          raise Errors::Internal, "Unexpected stargazer node: #{object.class}"
        end
      end

      field :node, Objects::User, null: false

      def node
        @object.node.async_user.then do |user|
          if user.nil?
            # We found an orphaned `Star`, whose `user_id` points to a non-existent user.
            err = Errors::Internal.new("Somehow got a Star without a user: #{@object.node.class.name} #{@object.node.attributes.inspect}")
            Failbot.report(err)
            # In this event, we'll return a ghost User instead of returning nil on a non-nullable field.
            ::User.ghost
          else
            user
          end
        end
      end

      field :starred_at, Scalars::DateTime, description: "Identifies when the item was starred.", null: false

      def starred_at
        @object.node.created_at
      end
    end
  end
end
