# typed: true
# frozen_string_literal: true

module ContextRegion
  class UserCrumb < Crumb
    include HovercardHelper

    def label
      object.display_login
    end

    def prefix_octicon
      object.user? ? :person : :organization
    end

    def parent
      if object.business.present? && options[:current_user]&.feature_enabled?(:enterprise_breadcrumbs) && object.business.user_connected_to_enterprise?(options[:current_user])
        BusinessCrumb.new(object.business, **options)
      else
        RootCrumb.new
      end
    end

    def path_name
      :user_path
    end

    def path_args
      [object]
    end

    def link_data_attrs(link_opts = {})
      attrs = if options[:hovercard] && link_opts[:include_hovercard]
        if object.user?
          hovercard_data_attributes_for_user(object, tracking: true)
        elsif object.organization?
          hovercard_data_attributes_for_org(login: object.display_login, tracking: true)
        end
      end

      attrs || {}
    end

    def header_navigation_component
      if object.user?
        Site::Header::UnderlineNavComponent.new(
          label: "User",
          tabs: User::NavigationTabs.for(user: object, current_user: options[:current_user], private_profile_override: options[:private_profile_override]),
          turbo_frame: "user-profile-frame"
        )
      elsif object.organization?
        org_nav = Organization::NavigationTabs.new(object, current_user: options[:current_user])

        Site::Header::UnderlineNavComponent.new(
          label: "Organization",
          tabs: org_nav.tabs,
          container_data_attrs: {
            url: org_nav.tab_counts_url
          },
          container_classes: ["js-profile-tab-count-container"]
        )
      end
    end
  end
end
