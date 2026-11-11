# typed: strict
# frozen_string_literal: true

module ContextRegion
  class UserCrumb < Crumb
    include GitHub::Memoizer
    include HovercardHelper

    sig { override.returns(String) }
    def label
      object.display_login
    end

    sig { override.returns(Symbol) }
    def prefix_octicon
      object.user? ? :person : :organization
    end

    sig { override.returns(Crumb) }
    def parent
      RootCrumb.new
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :user_path
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      [object]
    end

    sig { override.params(link_opts: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
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

    sig { override.returns(Symbol) }
    def crumb_type
      object.organization? ? :organization : :user
    end

    sig { override.returns(T.nilable(Site::Header::UnderlineNavComponent)) }
    def header_navigation_component
      if object.user?
        Site::Header::UnderlineNavComponent.new(
          label: "User",
          tabs: navigation_tabs.tabs,
          turbo_frame: "user-profile-frame"
        )
      elsif object.organization?
        Site::Header::UnderlineNavComponent.new(
          label: "Organization",
          tabs: navigation_tabs.tabs,
          container_data_attrs: {
            url: T.must(navigation_tabs.tab_counts_url),
          },
          container_classes: ["js-profile-tab-count-container"]
        )
      end
    end

    sig { override.returns(T.nilable(Primer::Component)) }
    def header_navigation_popover_component
      nil
    end

    sig { override.params(user: T.nilable(User), current_copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User))).returns(T.nilable(ContextRegion::LocalNavigation::TabPayload)) }
    def tab_payload(user: nil, current_copilot_user: nil)
      ContextRegion::LocalNavigation::TabPayload.new(
        current_user: user,
        context_object: object,
        navigation_tabs: navigation_tabs
      )
    end

    sig { override.returns(ContextRegion::LocalNavigation::NavigationTabs) }
    memoize def navigation_tabs
      if object.organization?
        Organization::NavigationTabs.new(object, current_user: options[:current_user], tab_popovers: options[:tab_popovers], on_org_profile_page: options[:on_org_profile_page])
      else
        User::NavigationTabs.new(object, current_user: options[:current_user], private_profile_override: options[:private_profile_override])
      end
    end

    private

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def popover
      navigation_tabs.popover
    end
  end
end
