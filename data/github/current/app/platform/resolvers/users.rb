# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Users < Resolvers::Base

      def self.inherited(child_class)
        super
        # Work around a cyclical load:
        child_class.type(Connections::User, null: false)
      end

      # Call this on some list of users to remove spammy ones.
      # Returns a list of the same kind, but without spammy ones.
      def filter_spam(users)
        case users
        when ArrayWrapper
          ArrayWrapper.new(users.reject { |u| u.hide_from_user?(context[:viewer]) })
        when Helpers::WatchersQuery
          users
        else
          users.filter_spam_for(context[:viewer])
        end
      end
    end
  end
end
