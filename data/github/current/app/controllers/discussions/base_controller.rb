# typed: true
# frozen_string_literal: true

class Discussions::BaseController < AbstractRepositoryController
  include OrganizationParamsHelper
  include Discussions::OrgLevelDiscussionsUrlHelper
  before_action :require_feature
  layout :determine_layout

  abstract!

  javascript_bundle :discussions
  stylesheet_bundle :discussions

  # Raised from the current_repository method when we can't
  # find the org based on params[:org], but we were able to
  # to find what the org was renamed to.
  class DiscussionOrgRenamed < StandardError
    attr_reader :org
    def initialize(org)
      @org = org
      super("Org #{org.display_login} has been renamed")
    end
  end

  rescue_from DiscussionOrgRenamed, with: :handle_renamed_discussion_org

  MAX_AVATARS = 21
  ONE_POINT_FIVE_TIMES_MAX_AVATARS = MAX_AVATARS * 1.5

  USER_CONTENT_FEATURES = [
    :discussions_release,
    :tasklist_block,
    :html_pipeline_bad_emoji,
    :ugc_inline_machine_translation,
    :sparkle_votes,
    :sparkle_votes_opt_out,
    :otel_rack_middleware,
    :issue_mention_filter_load_installation_for_source_repo,
    :emu_vss_business,
  ].freeze

  protected

  # Overrides RepositoryControllerMethods#current_repository
  sig { returns T.nilable(Repository) }
  memoize def current_repository
    return super unless params[:org]

    # For org-level discussions we need to set the repo to the target repo
    if params[:org]
      org = find_org

      return unless org.present?
      return unless org.discussion_repository.present?

      config = org.discussion_repository
      config&.repository.presence
    end
  end

  sig { returns T.nilable(Organization) }
  def find_org
    org = Organization.find_by(login: params[:org])
    return org if org.present?

    # We can't check this feature flag based on a repo or an org because we don't have enough
    # information to find one based on the URL at this point in the request lifecycle.
    # We have to check it based on the current user.
    renamed_org = RenamedOrganizationFinder.for_original_name(params[:org])
    raise DiscussionOrgRenamed.new(renamed_org) if renamed_org.present?

    nil # return nil explicitly for clarity
  end

  sig { returns T.nilable(String) }
  memoize def org_param
    referring_params[:org].presence || params[:org]
  end

  sig { returns T::Boolean }
  def is_org_level?
    params.key?(:org)
  end
  helper_method :is_org_level?

  # Used for org-level discussions
  sig { returns T.nilable(Organization) }
  memoize def this_organization
    if org_login_param.present?
      Organization.find_by_login(org_login_param)
    elsif current_repository&.organization_id
      T.must(current_repository).organization
    end
  end
  helper_method :this_organization

  private

  # Private: Overrides RepositoryControllerMethods#render_locked_repo_for_staff.
  sig { override.void }
  def render_locked_repo_for_staff
    # If we're loading org-level discussions, render 404 instead of the repo locked notice for staff viewers.
    is_org_level? ? render_404 : super
  end

  sig { returns String }
  def determine_layout
    is_org_level? ? "organization_discussions" : "repository"
  end

  # This handler is overridden in the Voltron::DiscussionsFragmentsController
  def handle_renamed_discussion_org(exception)
    GitHub.logger.info(
      "Renamed org discussion redirect",
      "code.namespace" => self.class.name,
      "code.function" => action_name,
      "gh.org.old_login" => params[:org],
      "gh.org.login" => exception.org.login, # rubocop:disable GitHub/DoNotAllowLogin used for logging
    )
    if action_name == "show"
      GitHub.dogstats.increment("renamed_org_discussion_redirects", tags: ["path:show"])

      redirect_to org_discussion_path(org: exception.org, number: params[:number]), status: :moved_permanently
    else
      render_404
    end
  end

  def show_stats
    Discussions::NullShowStats.new
  end

  sig { void }
  def require_feature
    render_404 unless discussions_enabled?
  end

  sig { void }
  def require_discussion
    # Read permissions are handled by privacy_check before_action
    # "Can this repo have discussions?" is handled by require_feature before_action
    render_404 unless discussion
  end

  sig { void }
  def require_comment
    render_404 unless comment && T.must(comment).readable_by?(current_user)
  end

  sig { void }
  def require_ability_to_open_discussion
    unless current_user.can_create_discussion?(current_repository)
      flash[:error] = "You can't perform that action at this time."
      redirect_to agnostic_discussions_path(org_param: org_param)
    end
  end

  sig { returns T.nilable(Discussion) }
  memoize def discussion
    current_repository = self.current_repository
    return nil unless current_repository

    discussion_number = params[:discussion_number].presence || params[:number]
    discussion = current_repository.discussions.
      filter_spam_for(current_user).
      with_number(discussion_number).first

    if discussion
      discussion.actor = current_user
    end

    discussion
  end
  helper_method :current_discussion
  alias_method :current_discussion, :discussion

  sig { returns(T.any(DiscussionTimeline::PaginatedRenderContext, DiscussionTimeline::SingleCommentRenderContext)) }
  def discussion_timeline_render_context
    DiscussionTimeline::PaginatedRenderContext.new(
      T.must(discussion),
      viewer: current_user,
      sort: timeline_sort,
      cap_filter: cap_filter,
      before_cursor: params[:before],
      after_cursor: params[:after],
      show_stats: show_stats,
    )
  end

  sig { returns DiscussionTimeline }
  memoize def discussion_timeline
    DiscussionTimeline.new(render_context: discussion_timeline_render_context)
  end

  sig { returns T.nilable(DiscussionComment) }
  memoize def comment
    discussion&.comments&.find_by(id: params[:comment_id])
  end

  def render_single_comment(target_comment, status: :ok, error_message: nil)
    render_context = DiscussionTimeline::SingleCommentRenderContext.new(
      discussion,
      target_comment,
      viewer: current_user,
      cap_filter: cap_filter
    )
    timeline = DiscussionTimeline.new(render_context: render_context)

    if target_comment.nested?
      render(Discussions::NestedCommentComponent.new(
        comment: target_comment,
        error_message: error_message,
        timeline: timeline,
      ), layout: false, status: status)
    else
      render(Discussions::CommentComponent.new(
        comment: target_comment,
        error_message: error_message,
        subscribe_to_live_updates: target_comment.nested_comments_count <= timeline.max_number_of_nested_comments_to_render,
        timeline: timeline,
      ), layout: false, status: status)
    end
  end

  def parsed_discussions_query=(value)
    @parsed_discussions_query = value
  end

  def parsed_discussions_query # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
    @parsed_discussions_query ||= Search::Queries::DiscussionQuery.normalize(
      Search::Queries::DiscussionQuery.parse(params[:discussions_q], current_user),
    )
  end
  helper_method :parsed_discussions_query

  attr_accessor :discussions_query_without_defaults
  helper_method :discussions_query_without_defaults

  sig { returns String }
  memoize def timeline_sort
    valid_sort_options = DiscussionTimeline::ItemFinder::VALID_SORT_OPTIONS
    sort = valid_sort_options.find { |option| option == params["sort"] }
    sort || DiscussionTimeline::ItemFinder::SORT_OLD
  end

  sig { void }
  def mark_discussion_timeline_as_read
    # Avoid race conditions when rendering multiple timeline fragments with voltron.
    # This way, only the fragment that renders the new marker will update the last_read_at.
    if discussion_timeline.will_render_new_marker?
      mark_discussion_as_read
    end
  end

  sig { void }
  def mark_discussion_as_read
    return unless logged_in?

    discussion = self.discussion
    return unless discussion

    # Use the latest hydrated time (in case there are updates while we're rendering)
    since = discussion.updated_at || Time.current

    last_read_at = discussion.last_read_at_for(viewer: current_user)

    # Only update the last read at if there have been changes
    if !last_read_at || last_read_at < since
      ActiveRecord::Base.connected_to(role: :writing) do
        discussion.set_last_read_at_for(viewer: current_user, time: since)
      end
    end
  end

  sig { returns T.nilable(T::Boolean) }
  def discussions_enabled?
    return false unless GitHub.discussions_available_on_platform?
    current_repository&.discussions_active? || is_org_level?
  end

  # We need to override the target for org level discussions because the
  # check for repositories looks for the `:user_id` param to find the repository
  # owner to use as the target.
  def target_for_conditional_access
    return this_organization if this_organization.present?
    super
  end

  # We need to override the resource for org level discussions
  # check for repositories looks for the `:user_id` param to find the repository
  # owner to use as the target.
  def resource_for_conditional_access
    discussion = self.discussion
    return this_organization if this_organization.present?
    return self unless discussion.present?
    discussion
  end
end
