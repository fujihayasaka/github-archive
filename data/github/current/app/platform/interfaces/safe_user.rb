# typed: true
# frozen_string_literal: true

# When implementing this interface in the platform objects, the object will need to have:
# - An active record association with a user  i.e. `belongs_to`, `has_one`
# - A `safe_user` method that returns the ghost user if user is nil, i.e. `user || User.ghost`
module Platform
  module Interfaces
    module SafeUser
      include Platform::Interfaces::Base

      description "Safe user field to return the user or fallback to the ghost user"
      visibility :internal

      field :safe_user, Interfaces::Actor, null: true, description: "The actor that created this object, will fall back to the ghost user if user was deleted", visibility: :internal

      def safe_user
        Platform::Loaders::ActiveRecordAssociation.load(@object, :user).then do |_user|
          @object.safe_user
        end
      end
    end
  end
end
