# typed: true
# frozen_string_literal: true

class Internal::FeedbackController < ApplicationController
  include InternalFeedbackHelper

  before_action :employee_only

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:search]

  def create
    repo, team_name = nil, nil
    if params[:feedback_target].blank?
      repo, team_name = find_feedback_recipient_info_from_ownership_doc(params[:logical_service])
    else
      repo, team_name = find_feedback_recipient_info_by_name(params[:feedback_target])
    end

    if !repo
      render plain: "Failed to create feedback issue. Couldn't find ownership info.", status: 422
      return
    end

    create_issue(repo, team_name, params)
  end

  def search # rubocop:todo GitHub/UseRestfulActions
    ownership_yaml_path = Rails.root.join("ownership.yaml")
    ownerships = YAML.safe_load(ownership_yaml_path.read)
    repo_names = ownerships["ownership"].filter_map do |ownership|
      repo_name = ownership["repo"].gsub("https://github.com/github/", "")
      repo_name if repo_name.include?(params[:q])
    end.uniq.shift(10)

    respond_to do |format|
      format.html_fragment do
        render partial: "stafftools/staffbar/feedback_target", formats: :html, locals: { repos: repo_names }
      end
      format.html do
        render partial: "stafftools/staffbar/feedback_target", locals: { repos: repo_names }
      end
      format.json { render json: { repo_names: repo_names } }
    end
  end

  private

  def create_issue(repo, team_name, params)
    # Find the Bug issue type for the organization
    bug_issue_type = Issues.domain.issue_types.by_organization(repo.owner_id).find { |type| type.name == "Bug" }

    # Find or create the "internal feedback" label
    internal_feedback_label = repo.labels.find_by_name("internal feedback")
    if !internal_feedback_label
      internal_feedback_label = repo.labels.create(
        name: "internal feedback",
        description: "Hubber submitted feedback"
      )
    end

    # Prepare title with "[Internal Feedback] " prefix
    prefixed_title = "[Internal Feedback] #{params[:issue][:title]}"

    # Prepare body with extra data appended
    extra_data = format_extra_data(request.referrer, params, team_name)
    full_body = "#{params[:issue][:body]}#{extra_data}"

    # Build issue attributes for domain service with all data included
    issue_attributes = Issues::CreateIssueAttributes.new(
      repository: repo,
      title: prefixed_title,
      body: full_body,
      issue_type: bug_issue_type,
      labels: [internal_feedback_label]
    )

    # Call domain service to create issue
    # Skip permission checks since this is an internal feedback system
    result = Issues.domain.create(issue_attributes, current_user, skip_permission_checks: true)

    case result
    when GH::Result::Ok
      issue = result.value
      respond_to do |format|
        format.json do
          render json: {
            url: issue.permalink(include_host: true),
            id: issue.id
          }
        end
      end
    when GH::Result::Error
      render plain: "issue invalid", status: 422
    end
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    return :no if %w(create).include?(action_name)
    super
  end

  def external_conditional_access_policy_enforceable
    return :no if %w(create).include?(action_name)
    super
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end

  def emu_ownership_enforceable
    :no
  end
end
