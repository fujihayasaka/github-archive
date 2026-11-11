# typed: true
# frozen_string_literal: true

class Copilot::Workbench::AbstractWorkbenchController < ApplicationController
  abstract!

  before_action :require_logged_in_user
  before_action :require_feature_enabled
  before_action :check_spark_trade_restrictions

  private

  sig { void }
  def require_logged_in_user
    render_404 unless logged_in?
  end

  sig { void }
  def require_feature_enabled
    render_404 unless current_user&.spark_workbench_preview_enabled?
  end

  sig { void }
  def check_spark_trade_restrictions
    return unless current_user&.feature_flag_enabled_or_raise?(:spark_trade_compliance) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    check_trade_compliance(target: current_user)
  end

  def resource_for_conditional_access
    return current_user if logged_in?
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    return current_user if logged_in?
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
