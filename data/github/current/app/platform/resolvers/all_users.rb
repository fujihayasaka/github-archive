# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class AllUsers < Resolvers::Users
      def resolve
        filter_spam(::User.where(type: "User"))
      end
    end
  end
end
