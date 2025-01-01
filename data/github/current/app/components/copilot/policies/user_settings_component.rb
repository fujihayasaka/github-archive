# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class UserSettingsComponent < ApplicationComponent

      sig do
        params(
          copilot_user: Copilot::User,
          disabled: T::Boolean,
          error: T::Boolean,
          submit_path: T.nilable(String),
          changed_settings: T.nilable(T::Hash[Symbol, T::Boolean]),
          view: T.nilable(Symbol),
          error_message: T.nilable(String)
        ).void
      end
      def initialize(copilot_user:, disabled: false, error: false, submit_path: nil, changed_settings: nil, view: nil, error_message: nil)
        @copilot_user = copilot_user
        @disabled = disabled
        @error = error
        @error_message = error_message
        @submit_path = submit_path
        @changed_settings = T.let(changed_settings || {}, T::Hash[Symbol, T::Boolean])
        @view = view
        @all_policies = T.let(nil, T.nilable(Copilot::Users::Policies::CopilotAllPolicies))
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def menu_items
        [
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed,
          Copilot::Policies::MenuItems::PublicCodeSuggestions::Blocked,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def automatic_code_review_menu_items
        [
          Copilot::Policies::MenuItems::AutomaticCodeReview::Enabled,
          Copilot::Policies::MenuItems::AutomaticCodeReview::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def a_chat_menu_items
        [
          Copilot::Policies::MenuItems::AChat::Enabled,
          Copilot::Policies::MenuItems::AChat::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def a_f_menu_items
        [
          Copilot::Policies::MenuItems::AF::Enabled,
          Copilot::Policies::MenuItems::AF::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def g_chat_menu_items
        [
          Copilot::Policies::MenuItems::GChat::Enabled,
          Copilot::Policies::MenuItems::GChat::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def o1_menu_items
        [
          Copilot::Policies::MenuItems::O1::Enabled,
          Copilot::Policies::MenuItems::O1::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def o3_menu_items
        [
          Copilot::Policies::MenuItems::O3::Enabled,
          Copilot::Policies::MenuItems::O3::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def o_ff_menu_items
        [
          Copilot::Policies::MenuItems::OFf::Enabled,
          Copilot::Policies::MenuItems::OFf::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def o_f_menu_items
        [
          Copilot::Policies::MenuItems::OF::Enabled,
          Copilot::Policies::MenuItems::OF::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def bing_menu_items
        [
          Copilot::Policies::MenuItems::BingGitHubChat::Enabled,
          Copilot::Policies::MenuItems::BingGitHubChat::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def overages_menu_items
        [
          Copilot::Policies::MenuItems::Overages::Enabled,
          Copilot::Policies::MenuItems::Overages::Disabled,
        ].map do |item|
          item.new(copilot_configurable: @copilot_user, type: "button").component
        end.compact
      end

      MICROSOFT_PRIVACY_STATEMENT_URL = "https://privacy.microsoft.com/en-us/privacystatement"
      sig { returns(String) }
      def microsoft_privacy_statement_url
        MICROSOFT_PRIVACY_STATEMENT_URL
      end

      sig { returns(String) }
      memoize def public_code_suggestion_setting
        if @copilot_user.allow_public_code_suggestions?
          "Allowed"
        elsif @copilot_user.block_public_code_suggestions?
          "Blocked"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def public_code_suggestion_value
        if public_code_suggestion_setting == "Allowed"
          "allowed"
        elsif public_code_suggestion_setting == "Blocked"
          "blocked"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def editor_preview_features_setting
        if editor_preview_features_enabled?
          "Enabled"
        elsif @copilot_user.editor_preview_features_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def editor_preview_features_value
        if editor_preview_features_setting == "Enabled"
          "enabled"
        elsif editor_preview_features_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def automatic_code_review_setting
        if automatic_code_review_enabled?
          "Enabled"
        elsif @copilot_user.automatic_code_review_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def automatic_code_review_value
        return "enabled" if automatic_code_review_enabled?
        return "disabled" if !automatic_code_review_enabled?
        ""
      end

      sig { returns(String) }
      memoize def a_chat_setting
        if a_chat_enabled?
          "Enabled"
        elsif @copilot_user.a_chat_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def a_chat_value
        if a_chat_setting == "Enabled"
          "enabled"
        elsif a_chat_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def a_f_setting
        if a_f_enabled?
          "Enabled"
        elsif @copilot_user.a_f_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def a_f_value
        if a_f_setting == "Enabled"
          "enabled"
        elsif a_f_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def g_chat_setting
        if g_chat_enabled?
          "Enabled"
        elsif @copilot_user.g_chat_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def g_chat_value
        if g_chat_setting == "Enabled"
          "enabled"
        elsif g_chat_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def o1_setting
        if o1_enabled?
          "Enabled"
        elsif @copilot_user.o1_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def o1_value
        if o1_setting == "Enabled"
          "enabled"
        elsif o1_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def o3_setting
        # TODO awaiting change to users/settings.rb, true for now
        if o3_enabled?
          "Enabled"
        elsif @copilot_user.o3_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def o3_value
        if o3_setting == "Enabled"
          "enabled"
        elsif o3_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def o_ff_setting
        # TODO awaiting change to users/settings.rb, true for now
        if o_ff_enabled?
          "Enabled"
        elsif @copilot_user.o_ff_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def o_ff_value
        if o_ff_setting == "Enabled"
          "enabled"
        elsif o_ff_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def o_f_setting
        # TODO awaiting change to users/settings.rb, true for now
        if o_f_enabled?
          "Enabled"
        elsif @copilot_user.o_f_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def o_f_value
        if o_f_setting == "Enabled"
          "enabled"
        elsif o_f_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      memoize def overages_setting
        if @copilot_user.overages_enabled?
          "Enabled"
        elsif @copilot_user.overages_disabled?
          "Disabled"
        else
          "Unconfigured"
        end
      end

      sig { returns(String) }
      def overages_value
        if overages_setting == "Enabled"
          "enabled"
        elsif overages_setting == "Disabled"
          "disabled"
        else
          ""
        end
      end

      sig { returns(String) }
      def dashboard_entry_point_value
        dashboard_entry_point_enabled? ? "enabled" : "disabled"
      end

      sig { returns(T::Boolean) }
      def error?
        @error
      end

      sig { params(value: Symbol).returns(T::Boolean) }
      def changed?(value)
        !!@changed_settings.fetch(value, false)
      end

      sig { returns(T::Boolean) }
      def onboarding?
        @view == :onboarding
      end

      sig { returns(T::Boolean) }
      memoize def has_individual_pro_access?
        @copilot_user.has_pro_access? || @copilot_user.has_pro_plus_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_enterprise_access?
        # Check if the user has a seat in an enterprise that has a Copilot Enterprise plan or is part of the Copilot Enterprise beta
        return true if copilot_businesses.any? do |business|
          Copilot::Business.new(business).has_copilot_enterprise_access?
        end

        Copilot::BusinessTrial.where(
          trialable_type: "Organization",
          trialable_id: copilot_organizations.pluck(:id),
          copilot_plan: "enterprise"
        ).active.any?
      end

      sig { returns(T::Boolean) }
      memoize def copilot_plan_individual?
        @copilot_user.copilot_plan_individual?
      end

      sig { returns(T::Boolean) }
      memoize def copilot_plan_individual_pro?
        @copilot_user.has_cfi_pro_plus_access?
      end

      sig { returns(T::Boolean) }
      memoize def bing_github_chat_enabled?
        @copilot_user.bing_github_chat_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def editor_preview_features_enabled?
        @copilot_user.editor_preview_features_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def automatic_code_review_enabled?
        @copilot_user.automatic_code_review_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def render_editor_preview_features_policy?
        return true if @copilot_user.feature_enabled?(:copilot_next_edit_suggestions) || editor_preview_features_enabled?
        false
      end

      sig { returns(T::Boolean) }
      memoize def a_chat_enabled?
        @copilot_user.a_chat_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def a_f_enabled?
        @copilot_user.a_f_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def g_chat_enabled?
        @copilot_user.g_chat_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def o1_enabled?
        @copilot_user.o1_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def render_o1_policy?
        return false if copilot_plan_individual?
        true
      end

      sig { returns(T::Boolean) }
      memoize def o3_enabled?
        @copilot_user.o3_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def o_ff_enabled?
        @copilot_user.o_ff_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def o_f_enabled?
        @copilot_user.o_f_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def render_a_f_policy?
        return true if @copilot_user.has_limited_access? && @copilot_user.feature_enabled?(:copilot_free_a_f)
        return false if @copilot_user.has_limited_access?
        true
      end

      sig { returns(T::Boolean) }
      memoize def render_o3_policy?
        return false if copilot_plan_individual?
        true
      end

      sig { returns(T::Boolean) }
      memoize def render_desktop_policy?
        return true if @copilot_user.has_limited_access? && @copilot_user.feature_enabled?(:copilot_desktop) && @copilot_user.feature_enabled?(:copilot_free_desktop)
        return false if @copilot_user.has_limited_access?

        @copilot_user.feature_enabled?(:copilot_desktop)
      end

      # If the configurable has "copilot_desktop_no_preview_badge" enabled then we will not show the "Preview"
      # beta badge. This is meant to be opt-in so users seeing the Preview beta badge is the default behavior.
      sig { returns(T::Boolean) }
      def desktop_policy_in_preview?
        !@copilot_user.feature_enabled?(:copilot_desktop_no_preview_badge)
      end

      sig { returns(T::Boolean) }
      memoize def render_o_ff_policy?
        return true if @copilot_user.has_limited_access? && @copilot_user.feature_enabled?(:copilot_o_ff) && @copilot_user.feature_enabled?(:copilot_free_o_ff)
        return false if @copilot_user.has_limited_access?
        return true if @copilot_user.feature_enabled?(:copilot_o_ff) || o_ff_enabled?
        return true if Copilot::Users::ModelAccess.model_available?(@copilot_user, :o_ff)
        false
      end

      sig { returns(T::Boolean) }
      memoize def render_o_f_policy?
        return true if @copilot_user.has_limited_access? && @copilot_user.feature_enabled?(:copilot_o_f) && @copilot_user.feature_enabled?(:copilot_free_o_f)
        return false if @copilot_user.has_limited_access?
        return true if @copilot_user.feature_enabled?(:copilot_o_f) || o_f_enabled?
        false
      end

      sig { returns(T::Boolean) }
      memoize def render_swe_agent_policy?
        return false if GitHub.multi_tenant_enterprise?

        # We only want to show the policy to users if they are pro+ or have a CE-licensed org
        return true if copilot_plan_individual_pro?
        return true if copilot_businesses.any? do |business|
          # Ensure that the user has at least one enterprise-licensed org
          Copilot::Business.new(business).copilot_organizations.any? do |org|
            org.copilot_enabled? && org.copilot_plan_enterprise?
          end
        end
        false
      end

      sig { returns(T::Boolean) }
      memoize def overages_enabled?
        @copilot_user.overages_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def render_overages_policy?
        return false if @copilot_user.has_limited_access? || !@copilot_user.feature_enabled?(:copilot_overages)
        true
      end

      sig { returns(T::Boolean) }
      memoize def dashboard_entry_point_enabled?
        @copilot_user.dashboard_entry_point_enabled?
      end


      sig { returns(String) }
      def copilot_policy_bing_value
        return "enabled" if bing_github_chat_enabled?
        return "disabled" if !bing_github_chat_enabled?
        ""
      end

      sig { returns(String) }
      memoize def copilot_policy_bing_text
        return "Enabled" if bing_github_chat_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_policy_editor_preview_features_text
        return "Enabled" if editor_preview_features_enabled?
        return "Disabled" if !editor_preview_features_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def automatic_code_review_text
        return "Enabled" if automatic_code_review_enabled?
        return "Disabled" if !automatic_code_review_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_policy_a_chat_text
        return "Enabled" if a_chat_enabled?
        return "Disabled" if !a_chat_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_policy_a_f_text
        return "Enabled" if a_f_enabled?
        return "Disabled" if !a_f_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_policy_g_chat_text
        return "Enabled" if g_chat_enabled?
        return "Disabled" if !g_chat_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_policy_o1_text
        return "Enabled" if o1_enabled?
        return "Disabled" if !o1_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_policy_o3_text
        return "Enabled" if o3_enabled?
        return "Disabled" if !o3_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_policy_o_ff_text
        return "Enabled" if o_ff_enabled?
        return "Disabled" if !o_ff_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_policy_o_f_text
        return "Enabled" if o_f_enabled?
        return "Disabled" if !o_f_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def dashboard_entry_point_text
        dashboard_entry_point_enabled? ? "Enabled" : "Disabled"
      end

      sig { returns(String) }
      memoize def copilot_extensions
        if @copilot_user.copilot_extensions_enabled?
          "Enabled"
        else
          "Disabled"
        end
      end

      sig { returns(String) }
      memoize def copilot_policy_overages_text
        return "Enabled" if overages_enabled?
        return "Disabled" if !overages_enabled?
        "Disabled"
      end

      sig { returns(String) }
      memoize def features_for_data_retention
        return "" unless @copilot_user.copilot_plan_business?

        features = []
        features << Copilot::CLI_UI_NAME if cli_configured?
        features << Copilot::COPILOT_IN_DOTCOM if has_copilot_enterprise_access?
        features << Copilot::COPILOT_CHAT_IN_MOBILE

        return "#{features.to_sentence} will collect additional data" if !features.empty?
        ""
      end

      sig { returns T::Boolean }
      memoize def cli_configured?
        @copilot_user.cli_configured?
      end

      sig { returns(T::Array[::Business]) }
      memoize def copilot_businesses
        copilot_organizations.map(&:business).compact
      end

      sig { returns(T::Array[::Organization]) }
      memoize def copilot_organizations
        copilot_seats.map(&:organization).compact
      end

      sig { returns(T::Array[Copilot::Seat]) }
      memoize def copilot_seats
        Copilot::Seat.for_user(@copilot_user.id).includes(organization: :business).order(:id).to_a
      end

      # Rendered when a non-Copilot for individuals user views their individual policies page
      sig { params(id: String, status_text: String).returns(String) }
      def render_enablement_text(id, status_text)
        icon = render(Primer::Beta::Octicon.new(icon: "shield-lock", size: :small, color: :muted))
        text = render(Primer::Beta::Text.new(id: id)) { status_text }

        render(Primer::Box.new) { "#{icon} #{text}".html_safe }.html_safe # rubocop:disable Rails/OutputSafety
      end

      # Wrapper for above method to reduce the logic in the html.erb
      sig { params(id: String, enabled: T::Boolean, force: T::Boolean).returns(String) }
      def render_read_only_enablement_text(id, enabled, force = false)
        return "" unless is_readonly_mode? || force
        status_text = enabled ? "Enabled" : "Disabled"
        render_enablement_text(id, status_text)
      end

      sig { returns(T::Boolean) }
      memoize def is_readonly_mode?
        @copilot_user.is_enterprise_managed? || @disabled
      end

      sig { returns(T::Boolean) }
      memoize def has_single_seat?
        copilot_seats.one?
      end

      sig { returns(T.nilable(T.any(Copilot::Organization, Copilot::Business))) }
      memoize def copilot_provider
        @copilot_user.copilot_provider
      end

      sig { returns(T.nilable(String)) }
      memoize def copilot_provider_path
        provider = copilot_provider&.__getobj__

        return if provider.nil?

        # copilot_provider is always guaranteed to be a business or an org
        if provider.is_a? ::Business
          enterprise_path(provider)
        else
          user_path(provider)
        end
      end

      sig { returns T::Boolean }
      memoize def copilot_access_through_org_or_business?
        @copilot_user.has_cfb_access? || @copilot_user.has_cfe_access?
      end

      sig { returns(T::Boolean) }
      memoize def limited_access_user?
        @copilot_user.has_limited_access?
      end

      sig { params(url: String, copy: String).returns(String) }
      def inline_docs_link(url, copy)
        link = render(Primer::Beta::Link.new(href: url, classes: "Link--inTextBlock")) { copy }
        link.html_safe # rubocop:disable Rails/OutputSafety
      end

      sig { params(policy: Symbol).returns(String) }
      def policy_blocked_by(policy)
        if @all_policies.nil?
          @all_policies = @copilot_user.all_policies
        end

        breakdown = T.let(@copilot_user.policy_breakdown(@all_policies, policy), Copilot::Users::Policies::CopilotSeatBreakdown)
        # This can also happen when an org policy says blocked in the org policy management page
        # but because the org has not explicitly choosen disabled (it's defaulting), the breakdown
        # does not show the org as blocking the policy.
        if breakdown[:disabled].empty? && breakdown[:enabled].empty?
          return "Your organization(s) have not enabled use of this feature."
        end

        return "" unless breakdown[:disabled].any?

        the_policy = breakdown[:disabled].first
        text = "This feature is blocked by "
        text += if the_policy[:type] == :organization
          render(Primer::Beta::Link.new(href: "/#{the_policy[:name]}", classes: "Link--inTextBlock")) { the_policy[:name] }
        elsif the_policy[:type] == :business
          render(Primer::Beta::Link.new(href: "/enterprises/#{the_policy[:name]}", classes: "Link--inTextBlock")) { the_policy[:name] }
        end

        if breakdown[:disabled].size > 1
          text += " and other organizations you are a member of."
        end

        text.html_safe # rubocop:disable Rails/OutputSafety
      end

      sig { returns(T::Boolean) }
      def show_custom_instructions_sso_banner?
        T.let(@copilot_user.user_object.feature_preview_enabled?(:copilot_chat_custom_instructions), T::Boolean) && unauthorized_orgs_with_custom_instructions.length > 0
      end


      sig { returns(T::Boolean) }
      def show_custom_instructions_options?
        T.let(@copilot_user.user_object.feature_preview_enabled?(:copilot_chat_custom_instructions), T::Boolean) && authorized_orgs_with_custom_instructions.length > 1
      end

      sig { returns(T::Array[::Organization]) }
      def unauthorized_orgs_with_custom_instructions
        org_ids = cap_filter
          .unauthorized(@copilot_user.organizations, only: :saml)
          .results
          .map { |r| r.resource.id }

        custom_instructions = helpers.get_custom_instructions(org_ids)

        custom_instructions.map { |ci| ci.owner }
      end

      sig { returns(T::Array[::Organization]) }
      def authorized_orgs_with_custom_instructions
        org_ids = cap_filter
          .authorized(@copilot_user.organizations, only: :saml)
          .results
          .map { |r| r.resource.id }

        custom_instructions = helpers.get_custom_instructions(org_ids)

        custom_instructions.map { |ci| ci.owner }
      end

      sig { returns(T::Array[::Organization]) }
      def orgs_with_custom_instructions
        custom_instructions = helpers.get_custom_instructions(@copilot_user.organizations.map(&:id))
        custom_instructions.map { |ci| ci.owner }
      end

      sig { returns(T.nilable(::Organization)) }
      def default_custom_instructions_org
        org_ids = authorized_orgs_with_custom_instructions.map(&:id)
        custom_instructions = helpers.get_default_custom_instructions(org_ids, @copilot_user.user_object)
        custom_instructions&.owner
      end

      sig { returns(T.nilable(Date)) }
      def limited_user_reset_date
        return nil unless @copilot_user.has_limited_access?

        @copilot_user.limited_user&.reset_date
      end

      sig { returns(T::Array[Customer]) }
      memoize def copilot_customers
        ids = Copilot::Public::User.new(@copilot_user.user_object).copilot_customer_ids
        Customer.where(id: ids).to_a
      end

      sig { returns(String) }
      def billable_customer_button_text
        if @copilot_user.billable_customer_id
          Customer.find_by(id: @copilot_user.billable_customer_id)&.name || ""
        else
          "Select billing entity"
        end
      end

      sig { returns(T::Boolean) }
      def render_billable_customer_menu?
        return false unless @copilot_user.feature_enabled?(:copilot_billable_entity_ui)
        return false if @copilot_user.has_cfi_access?

        copilot_customers.count > 1
      end

      sig { returns(String) }
      def enabled_copilot_premium_products
        coding_agent_enabled = @copilot_user.feature_enabled?(:billing_coding_agent_enabled) && has_copilot_enterprise_access?
        spark_enabled = @copilot_user.feature_enabled?(:copilot_workbench_user_limits)
        if coding_agent_enabled && spark_enabled
          " (Copilot, Spark, and Copilot coding agent)"
        elsif coding_agent_enabled
          " (Copilot and Copilot coding agent)"
        elsif spark_enabled
          " (Copilot and Spark)"
        else
          ""
        end
      end

      private

      sig { returns(String) }
      def subtext
        parts = [
          "You can use Copilot Chat in GitHub.com",
          limited_access_user? ? nil : "Copilot for pull requests",
          @copilot_user.has_knowledge_bases? ? "knowledge base search" : nil,
        ].compact.to_sentence

        render(
          Primer::Beta::Text.new(
            col: 10,
            color: :muted,
            id: "copilot_dotcom_setting_label",
            mb: 2,
            mr: 6,
            tag: :p,
          ),
        ) do
          safe_join(
            [
              "#{parts}.",
              "Copilot code review and preview features are only available for paid licenses.",
              "#{inline_docs_link(Copilot::COPILOT_DOTCOM_CHAT_DOCUMENTATION, "Learn more about Copilot in GitHub.com")}.",
            ],
            " ",
          )
        end
      end
    end
  end
end
