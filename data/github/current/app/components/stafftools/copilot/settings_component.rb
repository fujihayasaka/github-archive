# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::SettingsComponent < ApplicationComponent

  sig { returns(Copilot::User) }
  attr_reader :configurable

  sig { returns(T::Boolean) }
  attr_reader :has_cfi_access

  sig { params(configurable: Copilot::User, has_cfi_access: T::Boolean).void }
  def initialize(configurable, has_cfi_access: true)
    @configurable = configurable
    @has_cfi_access = has_cfi_access
    @all_policies = T.let(nil, T.nilable(Copilot::Users::Policies::CopilotAllPolicies))
  end

  private

  sig { returns(Copilot::Public::User) }
  memoize def public_user
    Copilot::Public::User.new(configurable.user_object)
  end

  sig { returns T::Boolean }
  memoize def telemetry_enabled?
    configurable.telemetry_enabled?
  end

  sig { returns String }
  memoize def public_code_suggestions_label
    return "Allow" if configurable.allow_public_code_suggestions?
    return "Block" if configurable.block_public_code_suggestions?
    "Unconfigured"
  end

  sig { params(value: String).returns(Symbol) }
  def public_code_suggestions_label_scheme(value)
    case value
    when "Allow"
      :success
    when "Block"
      :danger
    else
      :default
    end
  end

  sig { returns T::Boolean }
  memoize def chat_enabled?
    configurable.chat_enabled?
  end

  sig { returns T::Boolean }
  memoize def mobile_chat_enabled?
    configurable.mobile_chat_enabled?
  end

  sig { returns T::Boolean }
  memoize def cli_enabled?
    configurable.cli_enabled?
  end

  sig { returns T::Boolean }
  memoize def desktop_enabled?
    configurable.desktop_enabled?
  end

  sig { returns T::Boolean }
  memoize def a_chat_enabled?
    public_user.a_chat_enabled?
  end

  sig { returns T::Boolean }
  memoize def a_f_enabled?
    public_user.a_f_enabled?
  end

  sig { returns T::Boolean }
  memoize def editor_preview_features_enabled?
    public_user.editor_preview_features_enabled?
  end

  sig { returns T::Boolean }
  memoize def automatic_code_review_enabled?
    public_user.automatic_code_review_enabled?
  end

  sig { returns T::Boolean }
  memoize def g_chat_enabled?
    public_user.g_chat_enabled?
  end

  sig { returns T::Boolean }
  memoize def o1_enabled?
    public_user.o1_enabled?
  end

  sig { returns T::Boolean }
  memoize def o3_enabled?
    public_user.o3_enabled?
  end

  sig { returns T::Boolean }
  memoize def o_ff_enabled?
    public_user.o_ff_enabled?
  end

  sig { returns T::Boolean }
  memoize def o_f_enabled?
    public_user.o_f_enabled?
  end

  sig { returns T::Boolean }
  memoize def dotcom_chat_enabled?
    configurable.dotcom_chat_enabled?
  end

  sig { returns T::Boolean }
  memoize def beta_features_github_chat_enabled?
    public_user.beta_features_github_chat_enabled?
  end

  sig { returns T::Boolean }
  memoize def user_feedback_opt_in_enabled?
    public_user.user_feedback_opt_in_enabled?
  end

  sig { returns T::Boolean }
  memoize def bing_github_chat_enabled?
    configurable.bing_github_chat_enabled?
  end

  sig { returns T::Boolean }
  memoize def mcp_enabled?
    public_user.mcp_enabled?
  end

  sig { returns T::Boolean }
  memoize def copilot_extensions_enabled?
    configurable.copilot_extensions_enabled?
  end

  sig { returns T::Boolean }
  memoize def content_exclusions_enabled?
    configurable.copilot_content_exclusion_enabled?
  end

  sig { returns T::Boolean }
  memoize def overages_enabled?
    public_user.overages_enabled?
  end

  sig { returns T::Boolean }
  memoize def swe_agent_enabled?
    public_user.swe_agent_enabled?
  end

  sig { params(enabled: T::Boolean, disabled: T::Boolean).returns(String) }
  def label(enabled, disabled)
    return "Enabled" if enabled
    return "Disabled" if disabled
    "Unconfigured"
  end

  sig { params(value: String).returns(Symbol) }
  def label_scheme(value)
    case value
    when "Enabled"
      :success
    when "Disabled"
      :danger
    else
      :default
    end
  end

  sig { params(policy: Symbol).returns(String) }
  def policy_blocked_by(policy)
    if @all_policies.nil?
      @all_policies = @configurable.all_policies
    end

    breakdown = T.let(@configurable.policy_breakdown(@all_policies, policy), Copilot::Users::Policies::CopilotSeatBreakdown)
    # This can also happen when an org policy says blocked in the org policy management page
    # but because the org has not explicitly choosen disabled (it's defaulting), the breakdown
    # does not show the org as blocking the policy.
    if breakdown[:disabled].empty? && breakdown[:enabled].empty?
      return "No organization(s) have enabled this feature."
    end

    return "" unless breakdown[:disabled].any?

    the_policy = breakdown[:disabled].first
    text = " • Blocked by "
    text += if the_policy[:type] == :organization
      render(Primer::Beta::Link.new(href: "/#{the_policy[:name]}", classes: "Link--inTextBlock")) { the_policy[:name] }
    elsif the_policy[:type] == :business
      render(Primer::Beta::Link.new(href: "/enterprises/#{the_policy[:name]}", classes: "Link--inTextBlock")) { the_policy[:name] }
    end

    if breakdown[:disabled].size > 1
      text += " and other organizations."
    end

    text.html_safe # rubocop:disable Rails/OutputSafety
  end
end
