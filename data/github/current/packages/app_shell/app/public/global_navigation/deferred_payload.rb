# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class DeferredPayload < BasePayload
    sig { returns(T.nilable(AccountSwitcher::Helper)) }
    attr_reader :account_switcher_helper

    sig { returns(T::Boolean) }
    attr_reader :user_can_create_organizations

    sig { returns(T::Boolean) }
    attr_reader :memex_enabled

    sig { returns(T::Boolean) }
    attr_reader :show_issue_create_link

    sig { returns(T::Boolean) }
    attr_reader :display_switch_account_popover

    sig do
      params(
        current_user: T.nilable(User),
        source: String,
        current_copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User)),
        current_repository: T.nilable(Repository),
        current_organization: T.nilable(Organization),
        account_switcher_helper: T.nilable(AccountSwitcher::Helper),
        user_can_create_organizations: T::Boolean,
        memex_enabled: T::Boolean,
        show_issue_create_link: T::Boolean,
        display_switch_account_popover: T::Boolean
      ).void
    end
    def initialize(
      current_user:,
      source:,
      current_copilot_user: nil,
      current_repository: nil,
      current_organization: nil,
      account_switcher_helper: nil,
      user_can_create_organizations: false,
      memex_enabled: false,
      show_issue_create_link: false,
      display_switch_account_popover: false
    )
      super(
        current_user: current_user,
        current_copilot_user: current_copilot_user,
        current_repository: current_repository,
        current_organization: current_organization,
        source: source
      )
      @account_switcher_helper = account_switcher_helper
      @user_can_create_organizations = T.let(user_can_create_organizations, T::Boolean)
      @memex_enabled = T.let(memex_enabled, T::Boolean)
      @show_issue_create_link = T.let(show_issue_create_link, T::Boolean)
      @display_switch_account_popover = T.let(display_switch_account_popover, T::Boolean)
    end

    sig { override.returns(String) }
    def route_id
      "deferredRoute"
    end

    sig { override.params(return_to: T.nilable(String)).returns(T::Hash[T.untyped, T.untyped]) }
    def payload(return_to: nil)
      GitHub.dogstats.time("global_navigation.deferred_payload", tags: tracking_tags) do
        {
          nav_menu: nav_menu_payload_data,
          user_menu: user_menu_payload_data(return_to: return_to),
          create_menu: create_menu_payload_data,
          agents_menu: agents_menu_payload_data,
          account_switch_dialog: account_switch_dialog_payload_data,
        }
      end
    end

    private

    sig { params(name: String, block: T.proc.returns(T::Hash[T.untyped, T.untyped])).returns(T::Hash[T.untyped, T.untyped]) }
    def with_sub_payload_fallback(name, &block)
      yield
    rescue => e
      GitHub.dogstats.increment(
        "global_navigation.deferred_payload.sub_payload_error",
        tags: tracking_tags + ["sub_payload:#{name}"]
      )
      Rails.logger.error("DeferredPayload #{name} failed: #{e.message}")
      {}
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def nav_menu_payload_data
      with_sub_payload_fallback("nav_menu") do
        NavMenuPayload.new(
          current_user: current_user,
          current_copilot_user: current_copilot_user_v2,
          source: source
        ).payload
      end
    end

    sig { params(return_to: T.nilable(String)).returns(T::Hash[T.untyped, T.untyped]) }
    def user_menu_payload_data(return_to: nil)
      with_sub_payload_fallback("user_menu") do
        UserMenuPayload.new(
          current_user: current_user,
          account_switcher_helper: account_switcher_helper,
          source: source
        ).payload(return_to: return_to)
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def create_menu_payload_data
      with_sub_payload_fallback("create_menu") do
        CreateMenuPayload.new(
          current_user: current_user,
          current_copilot_user: current_copilot_user_v2,
          current_repository: current_repository,
          current_organization: current_organization,
          user_can_create_organizations: user_can_create_organizations,
          memex_enabled: memex_enabled,
          show_issue_create_link: show_issue_create_link,
          source: source
        ).payload
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def agents_menu_payload_data
      with_sub_payload_fallback("agents_menu") do
        CopilotPayload.new(
          current_user: current_user,
          current_copilot_user: current_copilot_user_v2,
          current_repository: current_repository,
          source: source
        ).agents_panel_payload
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def account_switch_dialog_payload_data
      with_sub_payload_fallback("account_switch_dialog") do
        AccountSwitchDialogPayload.new(
          current_user: current_user,
          account_switcher_helper: account_switcher_helper,
          display_switch_account_popover: display_switch_account_popover,
          source: source
        ).payload
      end
    end
  end
end
