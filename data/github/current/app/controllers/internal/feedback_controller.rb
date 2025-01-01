# typed: true
# frozen_string_literal: true

class Internal::FeedbackController < ApplicationController
  include InternalFeedbackHelper
  include Issues::Domain::Provider

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

    builder_args = params.permit!.to_h.with_indifferent_access
    builder_args[:issue][:issue_type_id] = issues_domain.issue_types.by_organization(repo.owner_id).find { |type| type.name == "Bug" }&.id

    issue = Issue::Builder.new(current_user, repo).build(builder_args)
    issue = add_label_and_extra_data(issue, team_name, request.referrer, params) if issue.valid?

    if issue.save
      respond_to do |format|
        format.json do
          render json: {
            url: issue.permalink(include_host: true),
            id: issue.id
          }
        end
      end
    else
      render plain: "issue invalid", status: 422
    end
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
