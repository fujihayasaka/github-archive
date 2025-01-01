# typed: true
# frozen_string_literal: true

class DiscussionsController < Discussions::BaseController
  include DiscussionsControllerMethods

  around_action :record_show_stats, only: :show

  # allow us to render more than 100 pages of discussions
  skip_before_action :cap_pagination, only: :index, unless: :robot?

  before_action :handle_transferred_discussion, only: :show
  before_action :require_feature, except: :index
  before_action :login_required, only: [:create, :update, :destroy]
  before_action :login_required_redirect_for_public_repo, only: :new
  before_action :handle_deleted_discussion, only: :show
  before_action :handle_issue_redirect, only: :show
  before_action :require_discussion, only: [:show, :update, :destroy]
  before_action :add_spamurai_form_signals, only: [:create, :update]
  before_action :set_org_context_crumb, if: :is_org_level?
  before_action :handle_choose_category_redirect, only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new],
    optional: true

  SHOW_FEATURES = USER_CONTENT_FEATURES + [
    :discussion_post_as_admin,
    :disable_discussions_notifications, # ThreadSubscriptionComponent
    :slash_commands, # PreviewableCommentFormComponent
    :structured_issue_comment_templates, # discussions/markdown_toolbar_template
    :issue_composer_security_link,
    :disable_azure_exp_cache,
    :notifications_async_discussions_subscription_button,
    :emu_vss_business,
    :interaction_limit_kv_fallback,
    :remove_shelf_limited_paths,
    :restrict_discussions_convert_to_issue,
    :discussion_post_as_admin,
    :disable_notifications_automatic_watching_repositories,
    :disable_notifications_automatic_watching_teams,
    :discussion_post_as_admin,
  ].freeze

  REPO_NAV_FEATURES = [
    :otel_rack_middleware,
    :allow_internal_org_config_repo_if_public_repos_disabled, # Global health repo for EMU orgs
    :global_health_files_repository_loader_new_fetch_implementation, # Global health repo for EMU orgs
    :copilot_conversational_ux_license_check,
    :copilot_for_partners,
    :copilot_natural_language_github_search,
    :reserved_domain,
    :remove_shelf_limited_paths,
  ]

  REDIS_JOB_HASHING_FEATURES = [
    :job_hash_lock_write_safe_key,
    :job_hash_lock_skip_unsafe_key_check,
    :job_hash_lock_skip_unsafe_key_write,
  ]

  preload_features REDIS_JOB_HASHING_FEATURES

  preload_features SHOW_FEATURES, only: :show
  preload_features REPO_NAV_FEATURES, only: [:index, :show, :new]
  preload_features [
    :discussion_post_as_admin,
    :add_notranslate_class,
    :tasklist_block,
    :issues_graph_api_disable_denormalized_read,
    :sparkle_votes,
    :sparkle_votes_opt_out,
    :discussions_top_filter_only_unlocked,
    :react_code_search_enabled,
    :emu_vss_business,
    :enterprise_banners_repo_level,
    :bus_ids_exclude_billing_manager_valid_license,
    :oidc_policy_enforced,
    :api_insights_rest,
    :optimize_single_repo_filter,
    :interaction_limit_kv_fallback,
    :primer_select_panel_use_experimental_non_local_form,
    :proxima_repository_advisories,
    :use_billing_locked_rather_than_disabled,
    :discussion_post_as_admin,
    :github_models_org_access_policies,
    :disable_notifications_automatic_watching_repositories,
    :disable_notifications_automatic_watching_teams,
  ], only: :index
  preload_features [
    :slash_commands,
    :structured_issue_comment_templates,
    :emu_vss_business,
    :enterprise_banners_repo_level,
    :bus_ids_exclude_billing_manager_valid_license,
    :oidc_policy_enforced,
    :api_insights_rest,
    :proxima_repository_advisories,
    :use_billing_locked_rather_than_disabled,
    :github_models_org_access_policies,
    :disable_notifications_automatic_watching_repositories,
    :disable_notifications_automatic_watching_teams,
    :discussion_post_as_admin,
  ], only: :new
  preload_features [
    :bus_ids_exclude_billing_manager_valid_license,
    :gitrpc_always_include_request_id,
    :stacks_toggle,
    :skip_open_graph_url_encoding,
    :notifyd_label_subscriptions,
    :two_factor_checkup,
    :notifications_async_watch_repo_button,
    :api_insights_rest,
    :owner_scoped_github_apps,
    :stafftools_tenant_use_parameter,
    :read_tree_entries_git,
    :spokesd_request_timeout_header,
    :enterprise_teams_org_assignment,
    :saml_satisfied_debug_logging,
    :enterprise_teams_org_authorization,
    :enterprise_teams_org_assignment,
    :erp_preview_enterprise_teams_org_assignment,
    :erp_staffship_enterprise_teams_org_assignment,
    :authzd_include_subject_organization_id
  ]

  javascript_bundle :"structured-issues"

  def index
    # Apply redirect for atom feed org discussions, but not when navigating to discussion category page
    current_category_param = params[:category_slug].presence
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    if current_repository.organization_discussion.present? && request.format.html? && !current_category_param
      return redirect_to org_discussions_path(current_repository.owner)
    end

    if !current_repository.discussions_active?
      if current_repository.show_landing_page?(current_user)
        return redirect_to discussions_landing_path(current_repository.owner, current_repository)
      else
        return render_404
      end
    end

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

      discussions = request_timing.track(:load_discussions) do
        load_discussions(
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
        cap_filter: cap_filter,
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
          interaction_allowed: can_interact_with_repo?,
        )
      end

      participants_by_discussion_id = request_timing.track(:preload_discussions_participants) do
        Discussion.participants_by_discussion_id(discussions, viewer: current_user)
      end

      set_hovercard_subject(current_repository)

      respond_to do |format|
        format.html do
          request_timing.track(:render_template) do
            render "discussions/index",
              locals: {
                permissions: discussions_permissions,
                query: sanitized_query_string,
                discussions: discussions,
                discussion_categories: categories_by_id.values,
                current_category: current_category,
                pinned_category_discussions: pinned_category_discussions,
                selected_category_slug: params["category_slug"],
                include_answer_filters: include_answer_filters?(params["category_slug"]),
                type_filter: type_filter,
                participants_by_discussion_id: participants_by_discussion_id,
                spotlights: spotlights,
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

  def show
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    if current_repository.organization_discussion.present? && !is_org_level?
      return redirect_to org_discussion_path(current_repository.owner, discussion.number)
    end

    if discussion.converting? || discussion.error?
      return render("discussions/show_conversion", locals: { discussion: discussion })
    end

    mark_discussion_as_read
    async_mark_thread_as_read discussion

    set_hovercard_subject(discussion)

    discussion_timeline.preload_comments

    DiscussionTimeline::PermissionPreloader.load_for(
      discussion_timeline,
      can_interact_with_repo: can_interact_with_repo?
    )

    unless discussion_timeline.render_voting_placeholders?
      DiscussionTimeline::VotesPreloader.load_for(discussion_timeline)
    end

    discussion_timeline.preload_body_html
    discussion_timeline.preload_labels

    limited_participants =
      discussion.participants_for(current_user, limit: ONE_POINT_FIVE_TIMES_MAX_AVATARS)

    respond_to do |format|
      format.html do
        render "discussions/show",
          locals: {
            discussion: discussion,
            timeline: discussion_timeline,
            participants: limited_participants,
            timeline_sort: timeline_sort,
          }
      end

      format.json do
        render json: { title: discussion.title }
      end

      # If the format isn't HTML or JSON, default to returning a 406
      format.all { head :not_acceptable }
    end
  end

  def new
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    if current_repository.organization_discussion.present? && !is_org_level?
      return redirect_to new_org_discussion_path(current_repository.owner)
    end

    discussion = current_repository.discussions.new

    can_create, can_create_announcements, can_label = Promise.all([
      current_user.async_can_create_discussion?(current_repository),
      current_repository.async_can_create_discussion_announcements?(current_user),
      discussion.async_labelable_by?(current_user),
    ]).sync

    unless can_create
      flash[:error] = "You can't perform that action at this time."
      redirect_to agnostic_discussions_path(current_repository, org_param: org_param)
      return
    end

    fields = PrefilledDiscussionsFields.new(
      params: params,
      repository: current_repository,
      user: current_user,
      can_create_announcements: can_create_announcements,
      can_label: can_label,
    )

    discussion.title = fields.title
    discussion.body = fields.body
    discussion.category = fields.category
    discussion.labels = fields.labels
    discussion.structured_template_inputs = fields.structured_template_inputs

    available_categories = current_repository.available_discussion_categories_for_actor(
      current_user,
      can_create_discussion_announcements: can_create_announcements,
    )

    render "discussions/new", locals: {
      discussion: discussion,
      welcome_message: params[:welcome_text],
      discussion_categories: available_categories,
      viewer_can_label: can_label,
    }
  end

  def create
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    unless current_user.can_create_discussion?(current_repository)
      flash[:error] = "You can't perform that action at this time."
      return redirect_to agnostic_discussions_path(current_repository, org_param: org_param)
    end

    discussion = Discussion::Builder.new(
      user: current_user,
      repository: current_repository,
    ).build(discussion_params: filtered_discussion_params, discussion_form_params: params[:discussion_form])
    first_discussion = !current_repository.discussions.any?

    if discussion.save
      if first_discussion
        current_repository.discussion_spotlights.create(
          preconfigured_color: DiscussionSpotlight.preconfigured_color_names.sample,
          pattern: DiscussionSpotlight.pattern_names.sample,
          discussion: discussion,
          spotlighted_by: current_user,
        )
        flash[:first_discussion] = true
      end
      redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    else
      include_announcements = current_repository.can_create_discussion_announcements?(current_user)
      available_categories = current_repository.available_discussion_categories_for_actor(
        current_user,
        can_create_discussion_announcements: include_announcements,
      )

      if discussion.category.present?
        render "discussions/new", status: :unprocessable_entity, locals: {
          discussion: discussion,
          welcome_message: params[:welcome_text],
          discussion_categories: available_categories,
          viewer_can_label: discussion.labelable_by?(current_user),
        }
      else
        # They attempted to create a discussion without a category, make them choose one
        flash[:error] = "Please choose a valid category for your discussion."
        render "discussions/choose/show", status: :unprocessable_entity, locals: {
          discussion_categories: available_categories
        }
      end
    end
  end

  def update
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    return render_404 if !discussion.modifiable_by?(current_user) && !discussion.category_modifiable_by?(current_user)

    if stale_model?(discussion)
      return render_stale_error(model: discussion,
        error: "Could not edit discussion. Please try again.", path: agnostic_discussion_path(discussion, org_param: org_param))
    end

    # Grab the poll's string representation as it is today, before we make any changes:
    old_poll_markdown = discussion.poll&.to_s

    # Update discussion attributes, including the poll question and options:
    assignable_parms = if discussion.modifiable_by?(current_user)
      discussion_params.except(:body)
    else
      discussion_params.slice(:category_id)
    end

    return render_404 if assignable_parms.empty? && !discussion.modifiable_by?(current_user)

    discussion.assign_attributes(assignable_parms)
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }

    if update_discussion(old_poll_markdown: old_poll_markdown)
      if request.xhr?
        render json: {
          "source" => discussion.body,
          "body" => discussion.body_html(context: { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }),
          "poll" => render_poll_html_string,
          "newBodyVersion" => discussion.body_version,
          "editUrl" => edits_menu_discussion_path(current_repository.owner,
            current_repository, discussion),
          "issue_title" => discussion.title,
          "page_title" => helpers.discussion_page_title(discussion),
          "category_id" => discussion.category_id,
        }
      else
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    else
      render_discussion_update_error
    end
  end

  def destroy
    discussion = self.discussion
    return render_404 unless discussion&.deletable_by?(current_user)

    deleter = DiscussionDeleter.new(discussion)

    if deleter.delete(current_user)
      if request.xhr?
        head :ok
      else
        redirect_to agnostic_category_path(discussion.category)
      end
    else
      if request.xhr?
        render json: discussion.errors.full_messages, status: :unprocessable_entity
      else
        flash[:error] = "Could not delete the discussion at this time."
        redirect_to agnostic_discussion_path(discussion, org_param: org_param)
      end
    end
  end

  private

  sig { params(category: T.nilable(DiscussionCategory)).returns(String) }
  def agnostic_category_path(category)
    category_slug = category&.slug

    if org_param.present?
      org_discussions_category_path(org: org_param, category_slug: category_slug)
    else
      current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
      category_path(current_repository.owner_display_login, current_repository, category_slug)
    end
  end

  def filtered_discussion_params
    params = discussion_params
    params = params.except(:post_as_admin) unless can_post_as_admin?

    params
  end

  def load_discussions(type_filter:, search_query:, categories:)
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
      current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
      current_repository.discussions.
        filter_spam_for(current_user).
        paginate(page: current_page, per_page: per_page).
        filter_by_type(type_filter).
        filter_by_categories(categories.pluck(:id)).
        recently_bumped_first
    end
  end

  def category
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    if params[:category_id].present?
      current_repository.available_discussion_categories.find_by(id: params[:category_id])
    else
      current_repository.fallback_discussion_category!
    end
  end

  memoize def sanitized_query_string
    Search::Queries::DiscussionQuery.stringify(parsed_discussions_query)
  end

  def render_discussion_update_error
    discussion = self.discussion
    return render_404 unless discussion

    poll = discussion.poll

    if request.xhr?
      errors = discussion.errors.full_messages
      errors += poll.errors.full_messages if poll
      return render json: { errors: errors }, status: :unprocessable_entity
    end

    flash[:error] = if poll && !poll.valid?
      "Could not edit the discussion's poll at this time."
    else
      "Could not edit the discussion at this time."
    end
    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  memoize def discussion_params
    params.require(:discussion).permit(
      :title,
      :first_time_discussions,
      :body,
      :category_id,
      :post_as_admin,
      poll_attributes: [
        :id,
        :question,
        options_attributes: %i[id option _destroy]
      ],
      labels: [],
    )
  end

  def handle_issue_redirect
    if discussion.nil? && number_param
      current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
      issue = current_repository.issues.find_by(number: number_param) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return unless issue

      if params[:converting] == "1"
        flash[:error] = "Unable to convert this issue to a discussion."
      end

      redirect_to issue_path(issue)
    end
  end

  def handle_deleted_discussion
    return if discussion

    deleted_discussion = DeletedDiscussion.for_repository(current_repository).
      with_number(number_param).first
    if deleted_discussion
      current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
      render "discussions/deleted", locals: {
        deleted_discussion: deleted_discussion,
        kql_query: "webevents | where repo_id == #{current_repository.id} | where action == \"discussion.destroy\" | where data.number == #{deleted_discussion.number}",
      }
    end
  end

  def handle_transferred_discussion
    transfer, transfer_exists = DiscussionTransfer.find_from(
      repository: current_repository,
      number: number_param,
    )

    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    has_feature_enabled = current_repository.discussions_active?

    if transfer
      new_repo = transfer.new_repository

      if new_repo&.readable_by?(current_user) && !new_repo.hide_from_user?(current_user)
        flash[:notice] = "This discussion was transferred here."
        return redirect_to transfer.new_discussion.permalink(include_host: false)
      elsif has_feature_enabled
        return render "discussions/transfer_no_access"
      end

      # If the transferred repo is not accessible and the current repo does not have
      # discussions enabled, we should just 404.
      render_404
    elsif transfer_exists
      return render_404 unless has_feature_enabled
      render "discussions/transfer_no_access", discussion_deleted: true
    end
  end

  def update_discussion(old_poll_markdown:)
    discussion = self.discussion
    return false unless discussion

    old_diff = Discussion.body_with_poll(discussion.body, old_poll_markdown)
    is_changing_poll = discussion_params[:poll_attributes].present?
    poll = discussion.poll
    if is_changing_poll && poll
      return false unless poll.save
    end
    new_poll_markdown = poll&.to_s

    if operation = TaskListOperation.from(params[:task_list_operation])
      new_body = operation.call(discussion.body)
      new_diff = Discussion.body_with_poll(new_body, new_poll_markdown)
      discussion.update_body(new_body, current_user, old_diff: old_diff, new_diff: new_diff)
    elsif discussion_params[:body] || is_changing_poll
      new_body = discussion_params[:body] || discussion.body
      new_diff = Discussion.body_with_poll(new_body, new_poll_markdown)
      discussion.update_body(new_body, current_user, old_diff: old_diff, new_diff: new_diff)
    else
      discussion.save
    end
  end

  memoize def show_stats
    if action_name == "show"
      ShowStats.new(
        discussion: discussion,
        viewer: current_user,
      )
    else
      super
    end
  end

  def record_show_stats
    show_stats.instrument_controller_action do
      yield
      response.successful?
    end
  end

  def max_allowed_page
    ::Search::Query::max_offset_default / per_page
  end

  def number_param
    request_coming_from_voltron? ? params[:discussion_number] : params[:number]
  end

  def render_poll_html_string
    discussion = self.discussion
    return "" unless discussion && discussion.category&.supports_polls?

    poll = discussion.poll
    return "" unless poll.present?

    render_to_string(
      Discussions::PollComponent.new(
        discussion_number: discussion.number,
        repository: current_repository,
        poll: poll,
        options: poll.options,
        preview: false,
        locked: discussion.locked?
      ),
      formats: [:html],
      layout: false
    )
  end
end
