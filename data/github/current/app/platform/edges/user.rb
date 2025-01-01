# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class User < Edges::Base
      description "Represents a user."


      def self.authorized?(object, context)
        if object.node.is_a?(::Following)
          if object.parent.id == object.node.following_id
            # If the parent User is the user being followed in the Following relationship,
            # then we must be returning followers, so check that the viewer is authorized
            # to see the follower.
            object.node.async_user.then do |follower|
              Objects::User.authorized?(follower, context)
            end
          else
            # If the parent User is the user doing the following in the Following relationship,
            # then we must be returning followed users, so check that the viewer is authorized
            # to see the followed user.
            object.node.async_following.then do |followed_user|
              Objects::User.authorized?(followed_user, context)
            end
          end
        else
          user = object.node
          Objects::User.authorized?(user, context)
        end
      end

      # This edge is usually used where `object.node` is a User, but in the case
      # of `User.following` and `User.followers`, `object.node` is a Following.
      #
      # In that case, we have to detect which direction the connection is going
      # (that is, "user to their followers" or "followers of this user"), then implement `#node`
      # according to that.
      def node
        if object.node.is_a?(::Following)
          user = object.parent
          following = object.node

          if user.id == following.following_id
            following.async_user # follower
          else
            following.async_following # followed user
          end
        else
          object.node # User
        end
      end
    end
  end
end
