# typed: true
# frozen_string_literal: true

class Orgs::DiscussionsController < Orgs::Controller
  include CurrentRepositoryInteractionsHelper
  include DiscussionsControllerMethods
  include RepositoryControllerMethods

  # allow us to render more than 100 pages of discussions
  skip_before_action :cap_pagination, only: :index, unless: :robot?

  before_action :set_org_context_crumb

  javascript_bundle :discussions
  stylesheet_bundle :discussions

  before_action :ensure_org_discussions_enabled
  before_action :require_current_repository

  layout "layouts/organization_discussions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  sig { void }
  def index
    current_repository = T.must_because(self.current_repository) { "#require_current_repository ensures non-nil" }
    list_flow = Discussion::ListControlFlow.new(
      params: params,
      parsed_discussions_query: parsed_discussions_query,
      repo: current_repository
    )

    return safe_redirect_to(list_flow.redirect_path) if list_flow.needs_redirection?

    # Set the unsullied query, which is used for rendering links on the sidebar.
    # This is the query before we add any default options, like `is:open`.
    self.discussions_query_without_defaults = parsed_discussions_query

    # Set the parsed query to include any default options that were set in
    # the `Discussion::ListControlFlow`.
    if request.format.html?
      self.parsed_discussions_query = list_flow.query
    end

    type_filter = params[:type]

    if parsed_discussions_query.present? && current_page > max_allowed_page
      render_404
    else
      categories = current_repository.available_discussion_categories
      categories_by_id = categories.index_by(&:id)

      discussions = request_timing.track(:load_org_discussions) do
        load_org_discussions(
          type_filter: type_filter,
          search_query: parsed_discussions_query,
          categories: categories,
        )
      end

      current_category = categories.find { |c| c.slug == params[:category_slug] }
      pinned_category_discussions = request_timing.track(:load_pinned_category_discussions) do
        if current_category.present?
          DiscussionCategoryPin.
            for_repository(current_repository).
            for_category(current_category).
            includes(:discussion).
            map(&:discussion)
        else
          []
        end
      end

      # The .to_a preloads the relation and prevents the .any? calls from performing an extra EXISTS query *then*
      # performing another, separate query to actually load the spotlight rows.
      spotlights = request_timing.track(:load_spotlights) do
        current_repository.discussion_spotlights.includes(:discussion).to_a
      end

      all_discussions = discussions + spotlights.filter_map(&:discussion) + pinned_category_discussions
      all_discussions.each do |discussion|
        discussion.repository = current_repository
        discussion.category = categories_by_id[discussion.category_id]
      end

      discussion_feed = DiscussionIndexFeed.new(
        repository: current_repository,
        discussions: discussions,
        all_discussions: all_discussions,
        viewer: current_user,
        cap_filter: cap_filter
      )
      request_timing.track(:feed_preload_for_display) do
        discussion_feed.preload_for_display
      end

      discussions_permissions = request_timing.track(:preload_permissions) do
        Discussion::IndexPermissionPreloader.load_for(
          repository: current_repository,
          discussions: discussions,
          categories: categories,
          viewer: current_user,
          interaction_allowed: can_interact_with_repo?
        )
      end

      participants_by_discussion_id = request_timing.track(:preload_discussions_participants) do
        Discussion.participants_by_discussion_id(discussions, viewer: current_user)
      end

      respond_to do |format|
        format.html do
          request_timing.track(:render_template) do
            render "orgs/discussions/index", locals: {
              repository: current_repository,
              current_category: current_category,
              permissions: discussions_permissions,
              query: sanitized_query_string,
              discussions: discussions,
              discussion_categories: categories_by_id.values,
              type_filter: type_filter,
              participants_by_discussion_id: participants_by_discussion_id,
              spotlights: spotlights,
              pinned_category_discussions: pinned_category_discussions,
              selected_category_slug: params["category_slug"],
              include_answer_filters: include_answer_filters?(params["category_slug"]),
              feed: discussion_feed
            }
          end
        end
        format.atom do
          set_header_for_no_index_and_no_follow
          render "discussions/feed", layout: false, locals: { discussions: discussions }
        end
      end
    end
  end

  private

  # Overrides the method in Orgs::Controller
  # If we can't find the org based on its slug, we'll check if the org was renamed
  # by way of any RepositoryRedirects.
  #
  # Returns nothing.
  sig { void }
  def this_organization_required
    if this_organization.nil?
      renamed_org = RenamedOrganizationFinder.for_original_name(params[:org])

      render_404 and return if renamed_org.nil?

      GitHub.logger.info(
        "Renamed org discussion redirect",
        "gh.org.old_login" => params[:org],
        "gh.org.login" => renamed_org.login, # rubocop:disable GitHub/DoNotAllowLogin used in logger context
      )

      if params[:category_slug].present?
        GitHub.dogstats.increment("renamed_org_discussion_redirects", tags: ["path:index_with_category"])
        redirect_to org_discussions_category_path(renamed_org, params[:category_slug])
      else
        GitHub.dogstats.increment("renamed_org_discussion_redirects", tags: ["path:index"])
        redirect_to org_discussions_path(renamed_org)
      end
    end
  end

  sig { returns T.nilable(OrganizationDiscussionConfig) }
  memoize def org_discussion_repo_config
    return unless this_organization.present?
    OrganizationDiscussionConfig.find_by(organization: this_organization)
  end

  sig { override.returns(T.nilable(Repository)) }
  memoize def current_repository
    super || org_discussion_repo_config&.repository
  end

  sig { void }
  def require_current_repository
    render_404 unless current_repository
  end

  sig { void }
  def ensure_org_discussions_enabled
    render_404 unless GitHub.discussions_available_on_platform? && org_discussion_repo_config.present?
  end

  sig { returns Integer }
  def max_allowed_page
    ::Search::Query::max_offset_default / per_page
  end

  def load_discussions(type_filter:, search_query:)
    if params[:discussions_q].present?
      Discussion::SearchResult.search(
        query: parsed_discussions_query,
        page: current_page,
        per_page: per_page,
        current_user: current_user,
        remote_ip: request.remote_ip,
        user_session: user_session
      )
    else
      scope = Discussion.includes(:repository).
        paginate(page: params[:page], per_page: per_page).
        filter_by_type(type_filter).
        recently_bumped_first
      this_organization&.visible_discussions_for(current_user, scope: scope)
    end
  end

  def load_org_discussions(type_filter:, search_query:, categories:)
    current_repository = T.must_because(self.current_repository) { "#require_current_repository ensures non-nil" }
    if search_query.present?
      Discussion::SearchResult.search(
        query: parsed_discussions_query,
        page: current_page,
        per_page: per_page,
        repo: current_repository,
        category_ids: categories.pluck(:id),
        current_user: current_user,
        remote_ip: request.remote_ip,
        user_session: user_session
      )
    else
      current_repository.discussions.
        filter_spam_for(current_user).
        paginate(page: current_page, per_page: per_page).
        filter_by_type(type_filter).
        filter_by_categories(categories.pluck(:id)).
        recently_bumped_first
    end
  end

  sig { returns String }
  memoize def sanitized_query_string
    Search::Queries::DiscussionQuery.stringify(parsed_discussions_query)
  end

  def parsed_discussions_query=(value)
    @parsed_discussions_query = value
  end

  sig { override.returns(T::Array[T.untyped]) }
  def parsed_discussions_query # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
    @parsed_discussions_query ||= Search::Queries::DiscussionQuery.normalize(
      Search::Queries::DiscussionQuery.parse(params[:discussions_q], current_user),
    )
  end
  helper_method :parsed_discussions_query

  attr_accessor :discussions_query_without_defaults
  helper_method :discussions_query_without_defaults

  sig { returns T.nilable(String) }
  def raw_discussions_search_query
    params[:discussions_q]
  end

  # We need to override the target for org level discussions because the
  # check for repositories looks for the `:user_id` param to find the repository
  # owner to use as the target.
  sig { returns T.any(Symbol, Organization) }
  def target_for_conditional_access
    this_organization || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  # We need to override the resource from definition in in app/controllers/repository_controller_methods.rb
  # that definition checks for repositories and looks for the `:user_id` param to find the repository
  def resource_for_conditional_access
    # defaulting to the target definition because it already handles organization
    self
  end

  # Private: Overrides RepositoryControllerMethods#render_locked_repo_for_staff.
  def render_locked_repo_for_staff
    # Since we're loading org-level discussions, render 404 instead of the repo locked notice for staff viewers.
    render_404
  end

  sig { override.returns(T::Boolean) }
  def is_org_level?
    true
  end
  helper_method :is_org_level?
end
