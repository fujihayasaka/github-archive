# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class AccountSwitchDialogPayload < BasePayload
    sig { returns(T.nilable(AccountSwitcher::Helper)) }
    attr_reader :account_switcher_helper

    sig { returns(T::Boolean) }
    attr_reader :display_switch_account_popover

    sig { override.returns(String) }
    def route_id
      "accountSwitchDialogRoute"
    end

    sig do
      params(
        current_user: T.nilable(User),
        source: String,
        account_switcher_helper: T.nilable(AccountSwitcher::Helper),
        display_switch_account_popover: T::Boolean
      ).void
    end
    def initialize(
      current_user:,
      source:,
      account_switcher_helper: nil,
      display_switch_account_popover: false
    )
      super(
        current_user: current_user,
        source: source
      )
      @account_switcher_helper = account_switcher_helper
      @display_switch_account_popover = display_switch_account_popover
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      GitHub.dogstats.time("global_navigation.account_switch_dialog", tags: tracking_tags) do
        return { show: false } unless account_switcher_helper && display_switch_account_popover

        {
          show: true,
          ownerLogin: current_user&.display_login,
          switchAccountPath: switch_account_path,
          stashedAccounts: account_switcher_helper&.stashed_accounts&.valid&.map do |account|
            {
              login: account.user.display_login,
              name: account.user.profile_name,
              avatarUrl: account.user.primary_avatar_url,
              userSessionId: account.user_session&.id,
            }
          end
        }
      end
    end
  end
end
