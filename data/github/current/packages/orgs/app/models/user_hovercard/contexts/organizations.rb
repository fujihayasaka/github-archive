# typed: true
# frozen_string_literal: true

module UserHovercard::Contexts
  class Organizations < Hovercard::Contexts::Base
    attr_reader :related, :user

    def initialize(related:, all:, user:, viewer: nil)
      @related = related
      @all = all
      @user = user
      @viewer = viewer
    end

    def message
      org_list = hovercard_sentence(highlighted, max: 3, total: total_organization_count) do |org|
        "@#{org.display_login}"
      end

      "Member of #{org_list}"
    end

    # Important organizations to show the full name of (in order)
    def highlighted
      return Organization.none if user.private_profile_for?(@viewer)
      return related if related.any?

      T.unsafe(Organization).ranked_for(user, scope: all)
    end

    def octicon
      "organization"
    end

    def total_organization_count
      all.count
    end

    def platform_type_name
      "OrganizationsHovercardContext"
    end

    private

    attr_reader :all
  end
end
