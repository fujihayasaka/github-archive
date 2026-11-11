# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class OrganizationsComponent < ApplicationComponent
      def initialize(profile_layout_data:)
        @profile_layout_data = profile_layout_data
      end

      def render?
        organizations.any?
      end

      private

      attr_reader :profile_layout_data

      delegate :profile_click_tracking_attrs, to: :helpers
      delegate :organizations, :organizations_count, :user_is_viewer?, to: :profile_layout_data

      def show_view_all?
        user_is_viewer? && organizations_count > Profiles::User::LayoutData::ORGANIZATIONS_LIMIT
      end

      def show_more_count?
        !user_is_viewer? && organizations_count > Profiles::User::LayoutData::ORGANIZATIONS_LIMIT
      end

      def more_count
        organizations_count - Profiles::User::LayoutData::ORGANIZATIONS_LIMIT
      end

      def org_link_data(organization_login)
        hovercard_data_attributes_for_org(login: organization_login)
          .merge(profile_click_tracking_attrs(:MEMBER_ORGANIZATION_AVATAR))
      end
    end
  end
end
