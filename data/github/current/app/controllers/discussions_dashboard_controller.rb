# typed: true
# frozen_string_literal: true

class DiscussionsDashboardController < ApplicationController
  before_action :login_required

  javascript_bundle :discussions
  stylesheet_bundle :discussions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  check_for_sso [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  # The following actions do not require conditional access checks:
  # - dashboard: serves `/discussions`, not consistently scoped to an organization.
  #   Enforcement may be required but should be done inline.
  # opted out to be handled manually in show action, filtering results
  CAP_OPT_OUT_ACTIONS = %w(index)

  def index
    context_region_title "Discussions"
    search_query = raw_discussions_search_query.presence && parsed_discussions_query
    discussions = if params[:discussions_q].present?
      search_discussions
    else
      load_visible_discussions
    end
    participants_by_discussion_id = Discussion.participants_by_discussion_id(discussions,
      viewer: current_user)

    render "discussions_dashboard/index", locals: {
      discussions: discussions,
      query: sanitized_query_string,
      participants_by_discussion_id: participants_by_discussion_id,
    }
  end

  private def two_factor_enforceable
    return :no if CAP_OPT_OUT_ACTIONS.include?(action_name)
    :yes
  end

  private def ip_allowlist_enforceable
    return :no if CAP_OPT_OUT_ACTIONS.include?(action_name)
    super
  end

  private def external_conditional_access_policy_enforceable
    return :no if CAP_OPT_OUT_ACTIONS.include?(action_name)
    super
  end

  private def require_active_external_identity_session?
    !CAP_OPT_OUT_ACTIONS.include?(action_name)
  end

  private

  memoize def sanitized_query_string
    Search::Queries::DiscussionQuery.stringify(parsed_discussions_query)
  end

  memoize def parsed_discussions_query
    Search::Queries::DiscussionQuery.normalize(
      Search::Queries::DiscussionQuery.parse(raw_discussions_search_query, current_user),
    )
  end
  helper_method :parsed_discussions_query

  def raw_discussions_search_query
    if params[:discussions_q].present?
      params[:discussions_q]
    elsif params[:created_by]
      "author:#{current_user.display_login}"
    elsif params[:commented]
      "commenter:#{current_user.display_login}"
    end
  end

  def search_discussions
    Discussion::SearchResult.search(
      query: parsed_discussions_query,
      page: params[:page],
      per_page: DEFAULT_PER_PAGE,
      current_user: current_user,
      remote_ip: request.remote_ip,
      user_session: user_session
    )
  end

  def load_visible_discussions
    discussions = if params[:commented]
      Discussion.commented_on_and_visible_to(current_user)
    else
      Discussion.authored_by_and_visible_to(current_user)
    end

    discussions = discussions.filter_spam_for(current_user).
      includes(:repository).
      recently_bumped_first

    authorized_discussions = cap_filter.authorized_resources(discussions)
    authorized_discussions.paginate(page: current_page, per_page: DEFAULT_PER_PAGE)
  end

  def target_for_conditional_access
    # Intentionally skipping the overall access check because the only endpoint in this controller, #index, returns
    # cross-repository results and does its own CAP filtering.
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
