# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewRepositorySettingsController < AbstractRepositoryController
  include ApplicationController::CopilotDependency
  include ApplicationController::VerifiedFetchDependency
  include Copilot::CodeReviewRepositorySettingsAccess

  allow_verified_fetch only: [:create]

  SETTING_ATTRIBUTE_NAMES = T.let(
    {
      "repo_custom_instructions_enabled" => :repo_custom_instructions_enabled,
      "repo_auto_approve_when_delegated" => :repo_auto_approve_when_delegated,
      "repo_qualified_approval_when_delegated" => :repo_qualified_approval_when_delegated,
      "repo_mcp_enabled" => :repo_mcp_enabled,
      "repo_review_effort_level" => :repo_review_effort_level,
    }.freeze,
    T::Hash[String, Symbol],
  )

  # Settings that use Rails enum (accept string values mapped to integers).
  ENUM_SETTINGS = T.let(
    %w[
      repo_review_effort_level
    ].freeze,
    T::Array[String],
  )

  # Subset of `repo_review_effort_level` enum values that are currently
  # supported. The `high` value is in the model's enum (so the column already
  # accepts it for future use) but is not yet supported end-to-end, so the
  # controller rejects it until the rollout is ready.
  SUPPORTED_REVIEW_EFFORT_LEVELS = T.let(
    %w[
      low
      medium
    ].freeze,
    T::Array[String],
  )

  skip_before_action :privacy_check, only: :create

  before_action :login_required
  before_action :ensure_admin_access, only: :create

  sig { void }
  def create
    return false unless current_repository

    setting_name = params[:setting].presence || "repo_custom_instructions_enabled"
    setting_attribute = SETTING_ATTRIBUTE_NAMES[setting_name]
    return head :bad_request unless setting_attribute
    return head :bad_request unless setting_enabled_for_current_rollout?(setting_name)
    return head :bad_request unless setting_allowed_for_current_repository?(setting_name)
    return head :bad_request if setting_forced_for_current_repository?(setting_name)

    setting_value = request_body_value || params[:value]

    # Validate the value before any database write. Doing this after
    # creating the settings record would create a row with default values for
    # invalid requests, which then changes downstream behavior (e.g. an
    # otherwise-unset repo would start emitting headers based on the default).
    if ENUM_SETTINGS.include?(setting_name)
      return head :bad_request unless setting_value_supported_for_current_rollout?(setting_name, setting_value)
    end

    repository = current_repository
    old_settings = snapshot_settings(repository)

    settings = settings_record_for(setting_name)

    if ENUM_SETTINGS.include?(setting_name)
      settings.public_send("#{setting_attribute}=", setting_value.presence)
    else
      settings.public_send("#{setting_attribute}=", setting_value == "1")
    end

    return head :bad_request unless settings.valid?

    settings.save!

    new_settings = T.must(snapshot_settings(repository))
    emit_setting_changed(repository, old_settings, new_settings)

    head :ok
  end

  private

  # JSON body parsing is globally disabled in this app
  # (ActionDispatch::Request.parameter_parsers.delete Mime[:json].symbol),
  # so we must manually extract values from JSON request bodies.
  sig { returns(T.nilable(String)) }
  def request_body_value
    return unless request.content_type&.include?("application/json")

    body = JSON.parse(request.body.read)
    return nil unless body.is_a?(Hash)

    body["value"]&.to_s
  rescue JSON::ParserError
    nil
  end

  sig { params(setting_name: String, value: T.nilable(String)).returns(T::Boolean) }
  def setting_value_supported_for_current_rollout?(setting_name, value)
    case setting_name
    when "repo_review_effort_level"
      SUPPORTED_REVIEW_EFFORT_LEVELS.include?(value)
    else
      true
    end
  end

  sig { params(setting_name: String).returns(T::Boolean) }
  def setting_enabled_for_current_rollout?(setting_name)
    case setting_name
    when "repo_auto_approve_when_delegated"
      auto_approve_reviews_feature_enabled?
    when "repo_qualified_approval_when_delegated"
      qualified_approval_setting_enabled_for_current_rollout?
    when "repo_mcp_enabled"
      mcp_feature_enabled?
    when "repo_review_effort_level"
      review_effort_level_feature_enabled?
    else
      true
    end
  end

  sig { params(setting_name: String).returns(T::Boolean) }
  def setting_allowed_for_current_repository?(setting_name)
    case setting_name
    when "repo_auto_approve_when_delegated"
      approval_policy.approval_delegated_to_repo?
    when "repo_qualified_approval_when_delegated"
      approval_policy.qualified_approval_delegated_to_repo? && approval_generation_effectively_enabled?
    else
      true
    end
  end

  sig do
    params(setting_name: String).returns(
      T.any(
        PullRequests::Copilot::CodeReviewRepositoryApprovalSettings,
        PullRequests::Copilot::CodeReviewRepositorySettings,
      ),
    )
  end
  def settings_record_for(setting_name)
    if approval_setting?(setting_name)
      T.cast(
        find_or_create_settings_record(PullRequests::Copilot::CodeReviewRepositoryApprovalSettings),
        PullRequests::Copilot::CodeReviewRepositoryApprovalSettings,
      )
    else
      T.cast(
        find_or_create_settings_record(PullRequests::Copilot::CodeReviewRepositorySettings),
        PullRequests::Copilot::CodeReviewRepositorySettings,
      )
    end
  end

  sig { params(settings_class: T.untyped).returns(T.untyped) }
  def find_or_create_settings_record(settings_class)
    repository = current_repository
    settings = T.unsafe(settings_class).find_by(repository: repository)
    return settings if settings

    T.unsafe(settings_class).create!(repository: repository)
  rescue ActiveRecord::RecordNotUnique
    settings = T.unsafe(settings_class).find_by(repository: repository)
    raise if settings.nil?

    settings
  end

  sig { params(setting_name: String).returns(T::Boolean) }
  def approval_setting?(setting_name)
    setting_name == "repo_auto_approve_when_delegated" ||
      setting_name == "repo_qualified_approval_when_delegated"
  end

  sig { returns(T::Boolean) }
  def review_effort_level_feature_enabled?
    !!Copilot::CodeReview::Features.preview_features_enabled_for_repo?(current_repository)
  end

  # Snapshot of the CCR repo settings. When no settings rows exist yet, this
  # returns nil so old_settings can distinguish first writes from default values.
  # Values are strings to match the audit-log settings hash shape that the
  # Hydro audit-log forwarder serializes.
  sig do
    params(repository: Repository).returns(T.nilable(T::Hash[String, String]))
  end
  def snapshot_settings(repository)
    repo_settings = PullRequests::Copilot::CodeReviewRepositorySettings.find_by(repository: repository)
    approval_settings = PullRequests::Copilot::CodeReviewRepositoryApprovalSettings.find_by(repository: repository)
    return nil unless repo_settings || approval_settings

    {
      "review_effort_level" => repo_settings&.repo_review_effort_level.presence || "unknown",
      "custom_instructions_enabled" => (!!repo_settings&.repo_custom_instructions_enabled).to_s,
      "auto_approve_when_delegated" => (!!approval_settings&.repo_auto_approve_when_delegated).to_s,
      "qualified_approval_when_delegated" => (!!approval_settings&.repo_qualified_approval_when_delegated).to_s,
      "mcp_enabled" => (!!repo_settings&.repo_mcp_enabled).to_s,
    }
  end

  sig do
    params(
      repository: Repository,
      old_settings: T.nilable(T::Hash[String, String]),
      new_settings: T::Hash[String, String],
    ).void
  end
  def emit_setting_changed(repository, old_settings, new_settings)
    return if old_settings == new_settings

    Copilot::Instrumenter.instrument_code_review_repository_settings_updated(
      repo: repository,
      actor: T.must(T.cast(current_user, T.nilable(::User))),
      old_settings: old_settings,
      new_settings: new_settings,
    )
  rescue StandardError => err
    # Telemetry must never fail the user's save. The settings update has
    # already been persisted at this point; swallow + report so the user
    # still gets a 200.
    Failbot.report(err)
  end
end
