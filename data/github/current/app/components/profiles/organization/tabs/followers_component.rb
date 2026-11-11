# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    module Tabs
      class FollowersComponent < ApplicationComponent
        include AvatarHelper
        include OrganizationsHelper

        def initialize(organization:, viewer:, followers:, user_session:, current_page:)
          @organization = organization
          @viewer = viewer
          @followers = followers
          @user_session = user_session
          @current_page = current_page
        end

        private

        attr_reader :organization, :viewer, :followers, :user_session, :current_page
        # Required for organization_meta_description
        alias :this_organization :organization

        def page_title
          "Followers · #{@organization.safe_profile_name}"
        end

        def organization_avatar_url(avatar_size)
          helpers.avatar_url_for(@organization, avatar_size)
        end

        def organization_login
          @organization.display_login
        end

        def organization_meta_description
          # This requires `this_organization` to be defined, hence the `alias` definition above.
          this_organization_meta_description
        end
      end
    end
  end
end
