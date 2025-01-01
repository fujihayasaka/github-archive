# typed: true
# frozen_string_literal: true

module ContextRegion
  class UserCrumb < Crumb
    include GitHub::Memoizer
    include HovercardHelper

    def label
      object.display_login
    end

    def prefix_octicon
      object.user? ? :person : :organization
    end

    def parent
      RootCrumb.new
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
      return unless navigation_tabs

      if object.user?
        Site::Header::UnderlineNavComponent.new(
          label: "User",
          tabs: T.must(navigation_tabs&.tabs),
          turbo_frame: "user-profile-frame"
        )
      elsif object.organization?
        Site::Header::UnderlineNavComponent.new(
          label: "Organization",
          tabs: T.must(navigation_tabs&.tabs),
          container_data_attrs: {
            url: T.must(navigation_tabs&.tab_counts_url),
          },
          container_classes: ["js-profile-tab-count-container"]
        )
      end
    end

    def header_navigation_popover_component
      if popover.present?
        Site::Header::NavigationTabPopoverComponent.new(
          heading: popover&.fetch(:heading, ""),
          body_text: popover&.fetch(:body_text, ""),
          notice: popover&.fetch(:notice, ""),
          dismiss_notice_href: popover&.fetch(:dismiss_notice_href, ""),
          cta: {
            text: popover&.fetch(:cta_text, ""),
            href: popover&.fetch(:cta_href, ""),
          },
        )
      end
    end

    private

    sig { returns(T.nilable(NavigationTabsInterface)) }
    memoize def navigation_tabs
      if object.user?
        User::NavigationTabs.new(object, current_user: options[:current_user], private_profile_override: options[:private_profile_override])
      elsif object.organization?
        Organization::NavigationTabs.new(object, current_user: options[:current_user])
      end
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def popover
      return unless navigation_tabs

      navigation_tabs&.popover
    end
  end
end
