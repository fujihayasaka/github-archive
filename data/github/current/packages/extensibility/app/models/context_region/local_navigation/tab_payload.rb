# typed: strict
# frozen_string_literal: true

# `TabPayload` provides a way to wrap NavigationTabs instances and serializes them for use in React payloads.

module ContextRegion
  module LocalNavigation
    class TabPayload
      extend T::Helpers

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(T.any(Business, User, Organization, Repository, Team)) }
      attr_reader :context_object

      sig { returns(T.nilable(String)) }
      attr_reader :update_channel

      sig { params(context_object: T.any(Business, User, Organization, Repository, Team), navigation_tabs: NavigationTabs, current_user: T.nilable(User), update_channel: T.nilable(String)).void }
      def initialize(context_object:, navigation_tabs:, current_user: nil, update_channel: nil)
        @current_user = current_user # current_user can be nil if the tabs are shown on a logged-out page (such as a public repo)
        @context_object = context_object
        @navigation_tabs = navigation_tabs
        @update_channel = update_channel
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def tabs
        @navigation_tabs.tabs.map { |underline_nav_tab| underline_nav_tab_to_hash(underline_nav_tab) }
      end

      private

      sig { params(underline_nav_tab: Site::Header::UnderlineNavTab).returns(T::Hash[Symbol, T.untyped]) }
      def underline_nav_tab_to_hash(underline_nav_tab)
        {
          id: underline_nav_tab.text.parameterize.to_sym,
          icon: underline_nav_tab.icon.to_s,
          label: underline_nav_tab.text,
          href: underline_nav_tab.href,
          selectedLinks: Array(underline_nav_tab.highlight),
          count: underline_nav_tab.count,
          popoverTarget: underline_nav_tab.popover_target?,
          popoverData: underline_nav_tab.popover_data,
          commandId: underline_nav_tab.data[:command_id],
          reactNav: {
            appTarget: underline_nav_tab.data[:react_nav],
            anchor: underline_nav_tab.data[:react_nav_anchor]
          },
          turboNav: {
            frame: underline_nav_tab.data_turbo_frame ? @navigation_tabs.turbo_frame : nil
          }
        }.compact
      end
    end
  end
end
