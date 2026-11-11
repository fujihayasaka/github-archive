# typed: strict
# frozen_string_literal: true

module PullRequestNudges
  class CopilotNudgePullRequestSidebarComponent < ApplicationComponent
    include ApplicationComponent::Rescuable
    include InProductTargeting::OrganizationNudgeConcern

    rescue_from StandardError, with: :nothing

    sig { returns T.nilable(Organization) }
    attr_reader :organization

    sig { returns String }
    attr_reader :nudge_category

    # One of { :disabled, :no_experience, :treatment_1, :treatment_2 }
    sig { returns Symbol }
    attr_reader :render_variant

    sig do
      params(
        organization: T.nilable(Organization),
        user: T.nilable(User),
        system_arguments: Primer::SystemArgumentsValue
      ).void
    end
    def initialize(
      organization:,
      user:,
      **system_arguments
    )
      @organization = organization
      @user = user

      experiment_id = "pr_ccr_admin_enable_policy_nudge"
      variant = -1

      if user.present?
        variant = hawaii_experiment_variant(
          experiment_id: experiment_id,
          user_id: user.id,
          variant_count: 3
        )
        variant = 0 if user.feature_flag_enabled?(:pr_show_ccr_primary_nudge_0, default: false)
        variant = 1 if user.feature_flag_enabled?(:pr_show_ccr_primary_nudge_1, default: false)
        variant = 2 if user.feature_flag_enabled?(:pr_show_ccr_primary_nudge_2, default: false)
        variant = -1 unless user.feature_flag_enabled?(:pr_show_ccr_primary_nudge, default: false)
      end

      render_variant_map = {
        -1 => :disabled,
        0 => :no_experience,
        1 => :treatment_1,
        2 => :treatment_2
      }

      @render_variant = T.let(render_variant_map[variant], Symbol)
      @nudge_category = T.let("pr_show_ccr_primary_nudge_#{variant}", String)
    end

    sig { returns T::Boolean }
    def render?
      return false if @render_variant == :disabled
      return false if @user.nil?
      return false if @organization.nil?

      return false unless eligible_for_pr_show_ccr_nudge?

      true
    end

    sig { returns T::Boolean }
    def eligible_for_pr_show_ccr_nudge?
      return false if @organization.nil? || @user.nil?
      return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || @user.is_enterprise_managed?
      return false unless @user.subscribed_to_in_product_messages?

      nudge_id = :pr_show_ccr_primary_nudge
      return false if @user.dismissed_organization_notice?(nudge_id.to_s, @organization)

      return false unless @organization.adminable_by?(@user)
      return false unless (
        GitHub::Plan.free_names.include?(@organization.plan.name) ||
        @organization.plan == GitHub::Plan.business
      )

      return false unless ::Copilot::Organization.new(@organization).has_copilot_for_business?

      return false if ::Copilot::Organization.new(@organization).code_review_enabled?

      true
    end
  end
end
