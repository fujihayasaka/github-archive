# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class BaseNavigationComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      def initialize(profile_layout_data:)
        @profile_layout_data = profile_layout_data
      end

      private

      attr_reader :profile_layout_data

      delegate(
        :repository_count,
        :profile_user,
        :user_is_viewer?,
        to: :profile_layout_data,
      )

      def profile_tab_link(url, tab_name:)
        options = selected?(tab_name) ? { "aria-current" => "page" } : {}
        data_attrs = helpers.profile_click_tracking_attrs(:"TAB_#{tab_name.upcase}").merge(
          "tab-item" => tab_name,
          "selected-links" => "#{tab_name} #{url}",
        )

        link_to(
          url,
          options.merge(
            class: class_names(
              "UnderlineNav-item js-responsive-underlinenav-item js-selected-navigation-item",
              "selected" => selected?(tab_name),
            ),
            data: data_attrs,
          ),
        ) do
          yield
        end
      end

      def selected?(tab_name)
        profile_layout_data.active_tab == tab_name.to_sym
      end

      def counter_component(count)
        Primer::Beta::Counter.new(count: count, round: true, hide_if_zero: true)
      end

      def icon_component(icon)
        Primer::Beta::Octicon.new(icon: icon, classes: "UnderlineNav-octicon", hide: :sm)
      end

      def user_overview_path
        overview_params = params[:preview] ? { preview: true } : {}

        @user_overview_path ||= user_path(profile_user, params: overview_params)
      end

      def user_repos_path
        repo_params = params[:preview] ? { preview: true, tab: "repositories" } : { tab: "repositories" }

        @user_repos_path ||= user_path(profile_user, params: repo_params)
      end
    end
  end
end
