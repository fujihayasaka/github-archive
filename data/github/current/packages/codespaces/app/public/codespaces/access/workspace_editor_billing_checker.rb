# typed: strict
# frozen_string_literal: true

module Codespaces
  module Access
    class WorkspaceEditorBillingChecker < Codespaces::Command
      sig { params(owner: T.untyped, billable_owner: T.untyped).void }
      def initialize(owner: nil, billable_owner: nil)
        @owner = owner
        @billable_owner = billable_owner
      end

      sig { override.params(prebuild: T::Boolean).returns(Codespaces::Access::AllowedResult) }
      def perform(prebuild: false)
        return AllowedResult.new(AllowedResult::DISALLOW_ENTITLEMENTS) unless @owner.present?
        return AllowedResult.new(AllowedResult::ALLOWED) unless should_check?
        monthly_usage = Codespaces::UsageRecord.
          for_workspace_editor.current.
          where(owner: @owner).
          sum(&:usage_seconds) || 0
        if monthly_usage < allowed_usage
          AllowedResult.new(AllowedResult::ALLOWED)
        else
          AllowedResult.new(AllowedResult::DISALLOW_ENTITLEMENTS)
        end
      end

      sig { returns(T::Boolean) }
      def should_check?
        return false unless @owner.present?
        return false if @billable_owner&.organization? && ::Copilot::Organization.new(@billable_owner).can_use_copilot_enterprise_features?
        return false if @owner&.feature_enabled?(:codespaces_hadron_no_limits)
        true
      end

      sig { returns(Integer) }
      def allowed_usage
        Codespaces::Dials::WorkspaceEditorIndividualUsageLimitSeconds.new(force_cache_miss: true).value
      end
    end
  end
end
