# typed: true
# frozen_string_literal: true

module Stafftools
  module Users
    class ProfileComponent < ApplicationComponent
      def initialize(user:, nodeinfo_cache_values:)
        @user = user
        @nodeinfo_cache_values = nodeinfo_cache_values
      end

      private

      attr_reader :user, :nodeinfo_cache_values

      delegate :current_repository, to: :helpers
      delegate :profile, to: :user, prefix: true

      def page_title
        "#{user.login} - Profile"
      end

      memoize def private_profile?
        user.private_profile?
      end
    end
  end
end
