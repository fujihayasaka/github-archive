# typed: false
# frozen_string_literal: true

module Actions
  module Policy
    class SelectedActionsOptionsForm < ApplicationForm
      form do |selected_actions_options_form|
        selected_actions_options_form.check_box_group do |check_box_group|
          check_box_group.check_box(
            name: "firstparty",
            value: "firstparty",
            label: "Allow actions created by GitHub",
            checked: github_owned_checked?,
            disabled: @disabled,
            data: {
              **@view_context.test_selector_hash("selected-actions-options")
            }
          )

          check_box_group.check_box(
            name: "marketplace",
            value: "marketplace",
            checked: verified_checked?,
            disabled: verified_disabled?,
            label: GitHub::HTMLSafeString.make(<<~HTML)
              Allow actions by Marketplace <a href="#{github_marketplace_url}">verified creators</a>
            HTML
          )
        end
      end

      def initialize(owner:, disabled: false)
        @owner = owner
        @disabled = disabled
      end

      def github_owned_checked?
        if @disabled
          @owner.highest_level_allowlist.github_owned_allowed?
        else
          @owner.allows_github_owned_actions?
        end
      end

      def verified_checked?
        if @disabled
          @owner.highest_level_allowlist.verified_allowed?
        else
          @owner.allows_verified_actions?
        end
      end

      def verified_disabled?
        @disabled || dotcom_connection_required?
      end

      def dotcom_connection_required?
        return false unless GitHub.dotcom_connection_enabled?
        !dotcom_connected? || !GitHub.dotcom_download_actions_archive_enabled?
      end

      def business_adminable_by_current_user?
        GitHub.global_business.owner?(@view_context.current_user)
      end

      def github_marketplace_url
        return @view_context.marketplace_path(type: "actions", verification: "verified_creator") unless GitHub.dotcom_connection_enabled?
        "https://github.com/marketplace?type=actions&verification=verified_creator"
      end

      def github_marketplace_docs_url
        "#{GitHub.enterprise_admin_help_url}/github-actions/enabling-automatic-access-to-githubcom-actions-using-github-connect"
      end

      private

      def dotcom_connected?
        GitHub::Connect.dotcom_connection.check_status == :connected
      end
    end
  end
end
