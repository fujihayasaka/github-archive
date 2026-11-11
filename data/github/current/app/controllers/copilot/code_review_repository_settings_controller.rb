# typed: true
# frozen_string_literal: true

class Copilot::CodeReviewRepositorySettingsController < AbstractRepositoryController
  include ApplicationController::CopilotDependency

  ALLOWED_SETTINGS = T.let(
    %w[
      repo_custom_instructions_enabled
      repo_auto_approve_enabled
      repo_auto_reject_enabled
    ].freeze,
    T::Array[String],
  )

  before_action :login_required

  sig { void }
  def create
    return false unless current_repository

    setting_name = params[:setting].presence || "repo_custom_instructions_enabled"
    return head :bad_request unless ALLOWED_SETTINGS.include?(setting_name)
    return head :bad_request unless setting_enabled_for_current_rollout?(setting_name)

    settings = PullRequests::Copilot::CodeReviewRepositorySettings.find_or_create_by(
      repository: current_repository,
    )

    settings[setting_name] = params[:value] == "1"

    settings.save!
    head :ok
  end

  private

  sig { params(setting_name: String).returns(T::Boolean) }
  def setting_enabled_for_current_rollout?(setting_name)
    case setting_name
    when "repo_auto_approve_enabled"
      auto_approve_reviews_feature_enabled?
    when "repo_auto_reject_enabled"
      auto_reject_reviews_feature_enabled?
    else
      true
    end
  end

  sig { returns(T::Boolean) }
  def merge_readiness_feature_enabled?
    current_repository.feature_enabled_for_repo_or_owner?(:ccr_show_merge_readiness)
  end

  sig { returns(T::Boolean) }
  def auto_approve_reviews_feature_enabled?
    merge_readiness_feature_enabled? && current_repository.feature_enabled_for_repo_or_owner?(:ccr_auto_approve_reviews)
  end

  sig { returns(T::Boolean) }
  def auto_reject_reviews_feature_enabled?
    merge_readiness_feature_enabled? && current_repository.feature_enabled_for_repo_or_owner?(:ccr_auto_reject_reviews)
  end
end
