# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class UserSettingsComponent < ApplicationComponent
      extend T::Sig

      sig do
        params(
          copilot_user: Copilot::User,
          disabled: T::Boolean,
          error: T::Boolean,
          submit_path: T.nilable(String),
          changed_settings: T.nilable(T::Hash[Symbol, T::Boolean]),
          view: T.nilable(Symbol)
        ).void
      end
      def initialize(copilot_user:, disabled: false, error: false, submit_path: nil, changed_settings: nil, view: nil)
        @copilot_user = copilot_user
        @disabled = disabled
        @error = error
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
        Copilot::Seat.for_user(@copilot_user.id).includes(organization: :business).to_a
      end

      # Rendered when a non-Copilot for individuals user views their individual policies page
      sig { params(id: String, status_text: String).returns(String) }
      def render_enablement_text(id, status_text)
        icon = render(Primer::Beta::Octicon.new(icon: "shield-lock", size: :small, color: :muted))
        text = render(Primer::Beta::Text.new(id: id)) { status_text }

        return text.html_safe unless has_single_seat? # rubocop:disable Rails/OutputSafety

        render(Primer::Box.new) { "#{icon} #{text}".html_safe }.html_safe # rubocop:disable Rails/OutputSafety
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
    end
  end
end
