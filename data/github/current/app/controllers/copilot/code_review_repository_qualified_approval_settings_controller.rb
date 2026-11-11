# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewRepositoryQualifiedApprovalSettingsController < AbstractRepositoryController
  include ApplicationController::CopilotDependency
  include ApplicationController::VerifiedFetchDependency
  include Copilot::CodeReviewRepositorySettingsAccess

  allow_verified_fetch only: [:update]

  skip_before_action :privacy_check, only: :update

  before_action :login_required
  before_action :ensure_admin_access, only: :update

  sig { void }
  def update
    return false unless current_repository

    request_body = request_body_params
    submitted_scope_when_enabled = submitted_qualified_approval_scope_when_enabled(request_body)
    submitted_file_patterns_text = submitted_qualified_approval_file_patterns_text(request_body)
    existing_settings = PullRequests::Copilot::CodeReviewRepositoryApprovalSettings.find_by(repository: current_repository)

    unless valid_qualified_approval_scope_when_enabled?(submitted_scope_when_enabled)
      return render_qualified_approval_update(
        status: :bad_request,
        message: "Invalid qualified approval file path limit selection.",
      )
    end

    unless qualified_approval_setting_enabled_for_current_rollout?
      return render_qualified_approval_update(
        status: :bad_request,
        message: "Qualified approvals are not available for this repository.",
      )
    end

    if force_qualified_approval_feature_enabled?
      return render_qualified_approval_update(
        status: :bad_request,
        message: "Qualified approval file path limits are not configurable while qualified approvals are forced on for this repository.",
      )
    end

    unless qualified_approval_setting_allowed_for_current_repository?
      return render_qualified_approval_update(
        status: :bad_request,
        message: "Qualified approvals must be enabled before saving file path limits.",
      )
    end

    retried_after_record_not_unique = T.let(false, T::Boolean)
    begin
      settings = existing_settings || PullRequests::Copilot::CodeReviewRepositoryApprovalSettings.new(
        repository: current_repository,
      )

      settings.assign_qualified_approval_scope_when_enabled(
        scope_when_enabled: submitted_scope_when_enabled,
        file_patterns_text: submitted_file_patterns_text,
      )

      if settings.save
        render_qualified_approval_update(
          status: :ok,
          message: "Saved approval file path settings.",
        )
      else
        render_qualified_approval_update(
          status: :unprocessable_entity,
          message: settings.errors.full_messages.to_sentence,
        )
      end
    rescue ActiveRecord::RecordNotUnique
      raise if retried_after_record_not_unique

      existing_settings = PullRequests::Copilot::CodeReviewRepositoryApprovalSettings.find_by(repository: current_repository)
      raise if existing_settings.nil?

      retried_after_record_not_unique = true
      retry
    end
  end

  private

  sig do
    params(
      status: Symbol,
      message: String,
    ).void
  end
  def render_qualified_approval_update(status:, message:)
    render json: { message: message }, status: status
  end

  # JSON body parsing is globally disabled in this app
  # (ActionDispatch::Request.parameter_parsers.delete Mime[:json].symbol), so
  # React verified-fetch requests need to be parsed manually.
  sig { returns(T::Hash[String, T.untyped]) }
  def request_body_params
    return {} unless request.content_type&.include?("application/json")

    body = JSON.parse(request.body.read)
    return body if body.is_a?(Hash)

    {}
  rescue JSON::ParserError
    {}
  end

  sig { params(request_body_params: T::Hash[String, T.untyped]).returns(String) }
  def submitted_qualified_approval_scope_when_enabled(request_body_params)
    submitted_value = request_body_params["repo_qualified_approval_scope_when_enabled"]
    submitted_value = params[:repo_qualified_approval_scope_when_enabled] if submitted_value.nil?

    Array(submitted_value).last.to_s.presence ||
      PullRequests::Copilot::CodeReviewRepositoryApprovalSettings::QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_ALL_FILES
  end

  sig { params(request_body_params: T::Hash[String, T.untyped]).returns(String) }
  def submitted_qualified_approval_file_patterns_text(request_body_params)
    submitted_value = request_body_params["qualified_approval_file_patterns"]
    submitted_value = params[:qualified_approval_file_patterns] if submitted_value.nil?

    submitted_value.to_s
  end

  sig { params(scope_when_enabled: String).returns(T::Boolean) }
  def valid_qualified_approval_scope_when_enabled?(scope_when_enabled)
    PullRequests::Copilot::CodeReviewRepositoryApprovalSettings::QUALIFIED_APPROVAL_SCOPE_WHEN_ENABLED_VALUES.include?(scope_when_enabled)
  end
end
