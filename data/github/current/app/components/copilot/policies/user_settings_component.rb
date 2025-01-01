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

      sig { returns(String) }
      memoize def public_code_suggestions_value
        return "blocked" if @copilot_user.block_public_code_suggestions?
        return "allowed" if @copilot_user.allow_public_code_suggestions?
        "unconfigured"
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
      memoize def has_individual_access?
        (@copilot_user.feature_flag_enabled?(:ccr_access_free, default: false) && limited_access_user?) || @copilot_user.has_trial_access? || @copilot_user.has_free_access? || @copilot_user.has_pro_access? || @copilot_user.has_pro_plus_access? || @copilot_user.has_max_access?
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
        @copilot_user.has_pro_plus_access?
      end

      sig { returns(T::Boolean) }
      memoize def editor_preview_features_enabled?
        @copilot_user.editor_preview_features_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def render_editor_preview_features_policy?
        return true if @copilot_user.feature_flag_enabled?(:copilot_next_edit_suggestions, default: false) || editor_preview_features_enabled?
        false
      end

      sig { returns(T::Boolean) }
      memoize def agent_mode_enabled?
        @copilot_user.agent_mode_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def render_agent_mode_policy?
        return false if copilot_plan_individual?
        return true if @copilot_user.feature_flag_enabled?(:copilot_agent_mode_show_policy, default: false)
        false
      end

      sig { returns(T::Boolean) }
      memoize def a_f_enabled?
        @copilot_user.a_f_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def render_o1_policy?
        return false if copilot_plan_individual?
        return false if @copilot_user.feature_flag_enabled?(:copilot_o1_policy_deprecated, default: false)
        true
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
        return true if @copilot_user.has_limited_access? && @copilot_user.feature_flag_enabled?(:copilot_free_a_f, default: false)
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
        return true if @copilot_user.has_limited_access? && @copilot_user.feature_flag_enabled?(:copilot_desktop, default: false) && @copilot_user.feature_flag_enabled?(:copilot_free_desktop, default: false)
        return false if @copilot_user.has_limited_access?

        @copilot_user.feature_flag_enabled?(:copilot_desktop, default: false)
      end

      # If the configurable has "copilot_desktop_no_preview_badge" enabled then we will not show the "Preview"
      # beta badge. This is meant to be opt-in so users seeing the Preview beta badge is the default behavior.
      sig { returns(T::Boolean) }
      def desktop_policy_in_preview?
        !@copilot_user.feature_flag_enabled?(:copilot_desktop_no_preview_badge, default: false)
      end

      sig { returns(T::Boolean) }
      memoize def render_o_ff_policy?
        return false if @copilot_user.feature_flag_enabled?(:copilot_o_ff_policy_deprecated, default: false)
        return true if @copilot_user.has_limited_access? && @copilot_user.feature_flag_enabled?(:copilot_o_ff, default: false) && @copilot_user.feature_flag_enabled?(:copilot_free_o_ff, default: false)
        return false if @copilot_user.has_limited_access?
        return true if @copilot_user.feature_flag_enabled?(:copilot_o_ff, default: false) || o_ff_enabled?
        return true if Copilot::Users::ModelAccess.model_available?(@copilot_user, :o_ff)
        false
      end

      sig { returns(T::Boolean) }
      memoize def render_o_f_policy?
        return true if @copilot_user.has_limited_access? && @copilot_user.feature_flag_enabled?(:copilot_o_f, default: false) && @copilot_user.feature_flag_enabled?(:copilot_free_o_f, default: false)
        return false if @copilot_user.has_limited_access?
        return true if @copilot_user.feature_flag_enabled?(:copilot_o_f, default: false) || o_f_enabled?
        false
      end

      sig { returns(T::Boolean) }
      memoize def render_swe_agent_policies?
        return false if GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, current_user, default: false)
        return true if copilot_plan_individual_pro?
        return true if copilot_plan_individual? || @copilot_user.has_trial_subscription?

        #check org for flag and plans
        return true if @copilot_user.copilot_organizations_including_trials.any? do |cp_org|
          enterprise_enabled = cp_org.copilot_plan_enterprise? || cp_org.on_free_copilot_enterprise_trial?
          business_enabled = cp_org.copilot_plan_business? || cp_org.on_free_copilot_business_trial?

          cp_org.copilot_enabled? && (enterprise_enabled || business_enabled)
        end

        #check business (if any) for flag and plans
        return true if @copilot_user.copilot_businesses_including_trials.any? do |business|
          enterprise_enabled = business.copilot_plan_enterprise? || business.on_free_copilot_enterprise_trial?
          business_enabled = business.copilot_plan_business? || business.business_object.trial?

          business.copilot_enabled? && (enterprise_enabled || business_enabled)
        end

        false
      end

      sig { returns(T::Boolean) }
      memoize def render_mcp_policy?
        return false if GitHub.multi_tenant_enterprise?
        return true if copilot_plan_individual_pro?
        return true if copilot_plan_individual?

        #check org for flag and plans
        return true if copilot_organizations.any? do |org|
          cp_org = Copilot::Organization.new(org)
          cp_org.copilot_enabled? && (cp_org.copilot_plan_enterprise? || cp_org.copilot_plan_business?)
        end

        #check business (if any) for flag and plans
        return true if @copilot_user.copilot_businesses.any? do |cp_business|
          cp_business.copilot_enabled? && (cp_business.copilot_plan_enterprise? || cp_business.copilot_plan_business?)
        end

        false
      end

      sig { returns(T::Boolean) }
      memoize def overages_enabled?
        @copilot_user.overages_enabled?
      end

      sig { returns(T::Boolean) }
      memoize def render_overages_policy?
        return false if @copilot_user.has_limited_access? || !@copilot_user.feature_flag_enabled?(:copilot_overages, default: false)
        true
      end

      sig { returns(String) }
      memoize def copilot_policy_a_f_text
        return "Enabled" if a_f_enabled?
        return "Disabled" if !a_f_enabled?
        "Disabled"
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
        if FeatureFlag.vexi.enabled?("copilot_ignore_access_revoked_for_user_seats", @copilot_user.user_object, default: false)
          return Copilot::Seat.without_access_revoked_for_user(@copilot_user.id).includes(organization: :business).order(:id).to_a
        end
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
      sig { params(id: String, enabled: T::Boolean, force: T::Boolean, enabled_text: String, disabled_text: String).returns(String) }
      def render_read_only_enablement_text(id, enabled, force = false, enabled_text: "Enabled", disabled_text: "Disabled")
        return "" unless is_readonly_mode? || force
        status_text = enabled ? enabled_text : disabled_text
        render_enablement_text(id, status_text)
      end

      sig { returns(T::Boolean) }
      memoize def is_readonly_mode?
        @copilot_user.is_enterprise_managed? || @disabled
      end

      sig { returns(T::Boolean) }
      memoize def has_single_seat?
        copilot_seats.one? && !@copilot_user.all_assignments_revoked?
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
        unauthorized_orgs_with_custom_instructions.length > 0
      end


      sig { returns(T::Boolean) }
      def show_custom_instructions_options?
        authorized_orgs_with_custom_instructions.length > 1
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

      sig { returns(T::Boolean) }
      def render_billing_section?
        !limited_access_user? && (render_copilot_overages_policy? || render_billable_customer_menu?)
      end

      sig { returns(T::Boolean) }
      memoize def render_copilot_overages_policy?
        @copilot_user.feature_flag_enabled?(:copilot_overages, default: false)
      end

      sig { returns(T::Array[{ name: String, id: Integer }]) }
      memoize def copilot_customers
        ids = Copilot::Public::User.new(@copilot_user.user_object).copilot_customer_ids
        Customer.where(id: ids).map do |customer|
          if @copilot_user.user_object.feature_flag_enabled?(:copilot_settings_billable_owners_name, default: false)
            name = customer.billable_owner&.name || customer.name
          else
            name = customer.name
          end
          { name: name, id: customer.id.to_s }
        end
      end

      sig { returns(String) }
      def billable_customer_button_text
        if @copilot_user.billable_customer_id
          if @copilot_user.user_object.feature_flag_enabled?(:copilot_settings_billable_owners_name, default: false)
            Customer.find_by(id: @copilot_user.billable_customer_id)&.billable_owner&.name || ""
          else
            Customer.find_by(id: @copilot_user.billable_customer_id)&.name || ""
          end
        else
          "Select billing entity"
        end
      end

      sig { returns(T::Boolean) }
      memoize def render_billable_customer_menu?
        return false unless @copilot_user.feature_flag_enabled?(:copilot_billable_entity_ui, default: false)
        return false if @copilot_user.has_cfi_access?

        copilot_customers.count > 1
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def quota_usage_partial_props
        {
          completionsPercentageUsed: completions_quota_used,
          chatPercentageUsed: chat_quota_used,
          anyQuotasExhausted: any_quota_exhausted?,
        }
      end

      sig { returns(Copilot::Public::User) }
      memoize def copilot_public_user
        Copilot::Public::User.new(@copilot_user.user_object)
      end

      sig { returns(Integer) }
      memoize def completions_quota_used
        (100 - copilot_public_user.quota_percentage_remaining(feature: "completions")).to_i
      end

      sig { returns(Integer) }
      memoize def chat_quota_used
        (100 - copilot_public_user.quota_percentage_remaining(feature: "chat")).to_i
      end

      sig { returns(T::Boolean) }
      def any_quota_exhausted?
        completions_quota_used == 100 || chat_quota_used == 100
      end

      sig { returns(T::Boolean) }
      def show_new_quota_ui?
        @copilot_user.feature_flag_enabled?(:copilot_ftp_quota_usage, default: false)
      end

      sig { returns(T::Boolean) }
      def new_ui_any_quota_exhausted?
        show_new_quota_ui? && any_quota_exhausted?
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def usage_footer_args
        {
          bg: new_ui_any_quota_exhausted? ? :attention : :subtle,
          px: new_ui_any_quota_exhausted? ? 2 : 3,
        }
      end

      sig { returns(String) }
      def enabled_copilot_premium_products
        # If billing_enable_coding_agent_product is enabled, we don't want to show Copilot coding agent as part of the combined text
        coding_agent_enabled = @copilot_user.feature_flag_enabled?(:billing_coding_agent_enabled, default: false) &&
          !@copilot_user.feature_flag_enabled?(:billing_enable_coding_agent_product, default: false) &&
          has_copilot_enterprise_access? &&
          !GitHub.multi_tenant_enterprise?
        # If billing_enable_spark_product is enabled, we don't want to show spark as part of the combined text
        spark_enabled = @copilot_user.user_object.spark_enabled? &&
          !@copilot_user.feature_flag_enabled?(:billing_enable_spark_product, default: false)
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

      sig { returns(T::Boolean) }
      def render_code_review_policy?
        return false unless code_review_policy_enabled?
        return true if has_individual_access?

        # check for eligible businesses
        return true if @copilot_user.copilot_businesses.any? do |cp_business|
          cp_business.feature_flag_enabled?(:copilot_code_review_policy, default: false) && cp_business.copilot_enabled? && (cp_business.copilot_plan_enterprise? || cp_business.copilot_plan_business?)
        end

        # check for eligible organizations
        return true if copilot_organizations.any? do |org|
          cp_org = Copilot::Organization.new(org)
          cp_org.feature_flag_enabled?(:copilot_code_review_policy, default: false) && cp_org.copilot_enabled? && (cp_org.copilot_plan_enterprise? || cp_org.copilot_plan_business?)
        end

        false
      end

      sig { returns(T::Boolean) }
      def code_review_policy_enabled?
        @copilot_user.feature_flag_enabled?(:copilot_code_review_policy, default: false)
      end

      private

      sig { returns(String) }
      def subtext
        parts = [
          "You can use Copilot Chat in GitHub.com",
          (limited_access_user? || code_review_policy_enabled?) ? nil : "Copilot for pull requests",
          @copilot_user.has_knowledge_bases? ? "knowledge base search" : nil,
        ].compact.to_sentence

        paid_license_features = code_review_policy_enabled? ? "Preview features" : "Copilot code review and preview features"

        safe_join(
          [
            "#{parts}. ",
            paid_license_features,
            " are only available for paid licenses. ",
            inline_docs_link(Copilot::COPILOT_DOTCOM_CHAT_DOCUMENTATION, "Learn more about Copilot in GitHub.com"),
            ".",
          ]
        )
      end
    end
  end
end
