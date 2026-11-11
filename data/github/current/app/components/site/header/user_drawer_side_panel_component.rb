# typed: true
# frozen_string_literal: true

module Site
  module Header
    class UserDrawerSidePanelComponent < SidePanelComponent
      include UsersHelper
      include InProductTargeting::DfdNudgeConcern

      attr_reader :account_switcher_helper

      def initialize(load_everything: false, account_switcher_helper: nil, **system_arguments)
        super(load_everything: load_everything, rich_content_enabled: true) # rich content for the user drawer does not need to be feature flagged

        @account_switcher_helper = account_switcher_helper
        @system_arguments = system_arguments
      end

      def user_menu_props
        GlobalNavigation::UserMenuPayload.new(
          current_user: user,
          account_switcher_helper: account_switcher_helper,
          source: "react_partial"
        ).payload(return_to: return_to_path)
      end

      def trigger_data
        data = super
        data.merge login: display_login
      end

      def display_login
        user.display_login
      end

      def primary_avatar_url
        user.primary_avatar_url
      end

      def user
        current_user
      end
    end
  end
end
