# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    module Tabs
      class FollowersListComponent < ApplicationComponent
        def initialize(organization:, followers:, current_page:)
          @organization = organization
          @followers = followers
          @current_page = current_page
        end

        private

        attr_reader :organization, :followers, :current_page

        def at_pagination_limit?
          helpers.at_pagination_limit?
        end
      end
    end
  end
end
