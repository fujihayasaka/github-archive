# typed: false
# frozen_string_literal: true

module DashboardHelper
  include UrlHelper

  ATOM_CONTENT_TYPES = ["atom", "application/atom+xml"].freeze
  GH_FOR_VSCODE_EXTENSION_ID = 797352.freeze

  TRENDING_REPOSITORY_EXP_ID = "Fe1445".freeze

  def atom_feed?
    return @_is_atom_feed if defined?(@_is_atom_feed)

    # No request/response when coming from MentionFilter in HTML pipeline
    is_atom_request = respond_to?(:request) && request && request.format.atom?
    is_atom_response = respond_to?(:response) && response &&
      ATOM_CONTENT_TYPES.include?(response.media_type)
    @_is_atom_feed = is_atom_request || is_atom_response
  end

  def feed_has_only_one_page_of_events?
    return false if current_page > 1
    event_count < Stratocaster::DEFAULT_PAGE_SIZE
  end

  def display_private_repo_limit_banner?
    return false unless logged_in?

    !current_user.ignored_upgrade? && current_user.at_plan_repo_limit? && !current_user.disabled?
  end

  def display_copilot_snippy_warning?
    return false unless logged_in?

    with_database_error_fallback(fallback: false) do
      current_copilot_user.can_modify_copilot_settings? && !current_copilot_user.public_code_suggestions_configured? &&
      !current_copilot_user.is_enterprise_managed?
    end
  end

  def display_copilot_trial_warning?
    return false unless logged_in?

    copilot_days_left_on_trial > 0 && copilot_days_left_on_trial <= 3
  end

  def copilot_days_left_on_trial
    return -1 unless logged_in?

    current_copilot_user.days_left_on_trial
  end

  def copilot_business_trial
    return unless logged_in?

    org_ids = current_user.owned_organizations.map do |org|
      org[:id]
    end

    with_database_error_fallback { Copilot::BusinessTrial.find_by(trialable_id: org_ids) }
  end

  def display_org_private_repo_limit_banner?
    org_admin? && !current_organization.ignored_upgrade? &&
      current_organization.at_plan_repo_limit? && !current_organization.disabled?
  end

  # Public: Returns true if the current user can change to another context on their dashboard.
  # This happens when a user belongs to an organization.
  def user_can_switch_contexts?
    current_user.dashboard_contexts.switchable?
  end

  # Public: True if the profile readme should be rendered
  #         for this viewer
  def show_profile_navigation?
    return false unless logged_in?
    current_user.profile_navigation_visible?
  end

  # Is the user a billing manager for the supplied orgs?
  #
  # Returns a Boolean.
  def user_is_billing_manager?(user, orgs)
    orgs.any? do |org|
      org.billing_manager_only?(user)
    end
  end

  def dashboard_news_feed_next_page_path
    if current_organization
      if FeatureFlag.vexi.enabled?(:conduit_org_feeds, current_user, default: false)
        org_dashboard_path(current_organization, page: current_page + 1)
      else
        organizations_news_feed_path(current_organization, page: current_page + 1)
      end
    else
      dashboard_news_feed_path(page: current_page + 1)
    end
  end

  def render_org_welcome
    if org_admin?
      render partial: "organizations/welcome_owner", locals: { org: current_organization }
    else
      render partial: "organizations/welcome", locals: { org: current_organization }
    end
  end

  TEACHER_ROLE_SHORT_TEXT = "role_teacher"
  STUDENT_ROLE_SHORT_TEXT = "role_student"

  def show_existing_user_github_education_banner?
    @show_github_education_banner = !dismissed_github_education_banner? && current_user.student_developer_pack_coupon?
  end

  def user_has_global_campus_dashboard_notice?
    return false unless FeatureFlag.vexi.enabled?(:global_campus_dashboard_notice, current_user, default: false)

    current_user.notices_for_dashboard.include?(UserNotice::DASHBOARD_GLOBAL_CAMPUS_NOTICE)
  end

  def show_new_user_github_education_banner?
    @show_github_education_banner = !dismissed_github_education_banner? && !current_user.student_developer_pack_coupon? &&
    (answered_role_as_student || edu_email_eligible? || user_has_global_campus_dashboard_notice?)
  end

  def dismissed_github_education_banner?
    return true if current_user.dismissed_notice?(UserNotice::DASHBOARD_GLOBAL_CAMPUS_NOTICE)
    false
  end

  def fetch_top_repositories(page:, per_page:, initial_per_page:)
    TopRepositories
      .for(viewer: current_user, since: 1.year.ago, cap_filter: cap_filter)
      .simple_paginate(page: page, per_page: per_page, initial_per_page: initial_per_page)
  end

  def fetch_paginated_teams(per_page:, initial_per_page: nil, current_page_for_teams: nil)
    visibility_scope = current_user.
      async_visible_teams_for(current_user).
      sync

    cap_authorized_team_ids = cap_filter.authorized_resource_ids(visibility_scope)

    Team.ranked_for(current_user, scope: visibility_scope).
      where(id: cap_authorized_team_ids).
      includes(:organization).
      simple_paginate(per_page: per_page, page: current_page_for_teams, initial_per_page: initial_per_page)
  end

  private

  def answered_role_as_student
    @answered_role_as_student ||= answered_role_question_as(role_short_text: STUDENT_ROLE_SHORT_TEXT)
  end

  # User has an .edu email and also did not answer the survey question with "Teacher"
  # Trying to avoid showing non-students with .edu emails the student pack CTA
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def edu_email_eligible?
    @edu_email_eligible ||= current_user.edu_email? && !answered_role_question_as(role_short_text: TEACHER_ROLE_SHORT_TEXT)
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def answered_role_question_as(role_short_text:)
    role_choice = user_identification_survey_role_question&.choices&.find_by(short_text: role_short_text)

    return false unless role_choice.present?

    user_identification_survey.answers_for(current_user).find_by(
      question_id: user_identification_survey_role_question.id,
      choice_id: role_choice.id,
    ).present?
  end

  def user_identification_survey
    @user_identification_survey ||= Survey.find_by_slug("user_identification")
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def user_identification_survey_role_question
    @user_identification_survey_role_question ||= user_identification_survey&.questions&.find_by(short_text: "user_role")
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def url_for_feed(query_params = {})
    opt_out = params[:opt_out_conduit_cache] == "true" && user_feature_enabled?(:feeds_conduit_cache_opt_out)

    if opt_out
      query_params[:opt_out_conduit_cache] = true
    end

    if params[:org] && user_or_global_feature_enabled?(:conduit_org_feeds)
      query_params[:org] = params[:org]
      conduit_org_feeds_path(params: query_params)
    else
      conduit_for_you_feed_path(params: query_params)
    end
  end
end
