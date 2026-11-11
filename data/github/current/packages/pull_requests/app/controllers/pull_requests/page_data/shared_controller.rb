# typed: true
# frozen_string_literal: true

class PullRequests::PageData::SharedController < AbstractRepositoryController
  include GitHub::RateLimitedRequest
  include JsonDependency
  include PullRequests::DiffContentLoadingHelper
  include FileFilterHelper
  include VerifiedFetchDependency
  include Copilot::Chat::FeatureVisibility

  allow_verified_fetch

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
      only: [:status_checks]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
      only: [:header]

  depends_on_clusters ApplicationRecord::Notify,
      # Note(@aliceclv): `thread_previews` has a temporary dependency on `Notify` caused by automated comments loaded from
      # the code scanning KV store.
      # Once we move out of the store, we can safely remove `thread_previews`
      only: [:header, :thread_previews],
      optional: true

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
      only: [:base_comparison_info]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:codeowners]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
      only: [:commits]

  depends_on_clusters ApplicationRecord::RepositoriesPushes,
      only: [:commits],
      optional: true

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
      only: [:merge_box]

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
      only: [:code_button]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
      only: [:tab_counts, :diffstat]

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
      only: [:description]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
      only: [:merge_instructions]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    optional: false, only: [:thread_previews]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
      optional: false, only: [:copilot_diff_chat, :copilot_code_review_show_upsell, :copilot_code_review_dismiss_upsell, :copilot_assisted_code_review_dismiss_upsell]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::SecurityProductsEnablement,
      optional: false, only: [:diff_entries]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::SecurityProductsEnablement,
      optional: false, only: [:diff_entry_lines]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
      optional: false, only: [:change_groups]

  READ_RATE_LIMIT = 400
  STATUS_CHECKS_UNAVAILABLE = "status checks are unavailable"
  RATE_LIMIT_REACHED = "Your browser sent requests too quickly"

  rate_limit_requests \
    only: [:status_checks, :commits, :merge_box, :merge_instructions],
    max: READ_RATE_LIMIT,  # per minute
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, # 1.minute
    key: :default_rate_limit_key,
    at_limit: :render_rate_limited_response

  before_action :load_pull_request, except: [:copilot_code_review_show_upsell, :copilot_code_review_dismiss_upsell, :copilot_assisted_code_review_dismiss_upsell]
  before_action :require_xhr
  before_action :try_parse_json_params, only: [:change_base, :update_title, :copilot_code_review_show_upsell, :copilot_code_review_dismiss_upsell, :copilot_assisted_code_review_dismiss_upsell]
  before_action :login_required, only: [:change_base, :update_title, :copilot_code_review_show_upsell, :copilot_code_review_dismiss_upsell, :copilot_assisted_code_review_dismiss_upsell, :merge_instructions, :status_checks, :merge_box]
  before_action :writable_repository_required, only: [:change_base, :update_title]

  skip_before_action :set_repo_as_hovercard_subject
  skip_before_action :authorization_required, only: :header

  def status_checks # rubocop:disable GitHub/UseRestfulActions

    GitHub.dogstats.distribution_time(
      "pull_request.page_data.status_checks",
      tags: ["loader:domain"],
    ) do
      status_checks = PullRequests::PageData::StatusChecks::Loader.load(
        repository: current_repository,
        pull_request: @pull_request,
        avatar_size:,
      )

      pull_request_pending_workflow_approval_summary = PullRequests::PageData::StatusChecks::PullRequestPendingWorkflowApprovalSummary.new(pull_request: @pull_request, current_user: current_user)

      if status_checks
        serializer = PullRequests::PageData::StatusChecksSerializer.new(
          status_checks: status_checks,
          pull_request: @pull_request,
          pull_request_pending_workflow_approval_summary: pull_request_pending_workflow_approval_summary,
          avatar_size: avatar_size,
          include_copilot_check_run_failure_context: can_show_copilot_action_in_mergebox_ui?,
        )

        render json: serializer.to_hash, status: :ok
      else
        render status: :internal_server_error, json: { error: STATUS_CHECKS_UNAVAILABLE }
      end
    end
  end

  def merge_box  # rubocop:disable GitHub/UseRestfulActions
    return head :not_found if @pull_request.nil?
    merge_requirements_data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(
      pull_request: @pull_request,
      repository: current_repository,
      merge_action: params[:merge_action],
      merge_method: params[:merge_method],
      bypass_requirements: params[:bypass_requirements] == "true",
      viewer: T.must(current_user),
    )

    merge_requirements = merge_requirements_data ? PullRequests::PageData::MergeBox::MergeRequirementsPayload.call(merge_requirements_data) : nil

    pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull_request, current_user:)
    pull_request_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
    merge_box_payload = {
      pullRequest: pull_request_payload,
      mergeRequirements: merge_requirements
    }.as_json

    render json: merge_box_payload, status: :ok
  end

  def merge_instructions # rubocop:disable GitHub/UseRestfulActions
    return head :not_found if @pull_request.nil?

    pull_request_data = PullRequests::PageData::MergeBox::MergeInstructionsLoader.load(pull_request: @pull_request, viewer: T.must(current_user))
    payload = PullRequests::PageData::MergeBox::MergeInstructionsPayload.build(pull_request_data)

    render json: payload, status: :ok
  end

  def header # rubocop:disable GitHub/UseRestfulActions
    payload = PullRequests::PageData::HeaderPayload.build(pull_request: @pull_request, current_user:)
    render json: payload.to_json, status: :ok
  end

  def update_title # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless current_user_can_push?
    return render_404 if blocked_by_owner?

    if @pull_request.issue.update(title_params) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
      render json: { pullRequest: { title: @pull_request.title, titleHtml: @pull_request.title_html } }, status: :ok
    else
      render json: { error: @pull_request.issue.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def change_base # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless new_base_binary = change_base_params[:new_base_binary]
    return render_404 unless @pull_request.issue.can_modify?(current_user)

    new_base = Base64.decode64(new_base_binary)
    if !new_base.present?
      return render json: { error: "Please select a base branch" }, status: :unprocessable_entity
    end

    result = PullRequests::ChangeBase.execute(pull_request: @pull_request, user: T.must(current_user), new_base:)

    case result
    when PullRequests::ChangeBase::Success
      render json: { orchestration: { url: pull_request_orchestration_status_url(orchestration_id: result.orchestration.id) } }
    when PullRequests::ChangeBase::Error
      render json: { error: result.error_message }, status: :unprocessable_entity
    else
      T.absurd(result)
    end
  end

  def commits # rubocop:disable GitHub/UseRestfulActions
    current_path = defined?(path_string_for_display) ? path_string_for_display : ""

    payload = PullRequests::PageData::CommitsPayload.build(
      current_path:,
      current_user:,
      pull_request: @pull_request,
      tree_name: tree_name_for_display,
    )
    render json: payload.to_json, status: :ok
  end

  def code_button # rubocop:disable GitHub/UseRestfulActions
    code_button_data = PullRequests::PageData::CodeButton::Loader.load(current_user: current_user, pull_request: @pull_request)
    payload = PullRequests::PageData::CodeButton::Payload.call(code_button_data)
    render json: payload.to_json, status: :ok
  end

  def description # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)


    description_data = PullRequests::PageData::Description::Loader.load(pull_request: @pull_request)
    payload = PullRequests::PageData::Description::Payload.call(description_data)

    respond_to do |format|
      format.json do
        render json: payload.to_json, status: :ok
      end
    end
  end

  def tab_counts # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)

    limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
      repository: current_repository,
      user: current_user,
    )

    tab_counts_data = PullRequests::PageData::TabCounts::Loader.load(pull_request: @pull_request, limit_config: limit_config)
    payload = PullRequests::PageData::TabCounts::Payload.call(tab_counts_data)

    respond_to do |format|
      format.json do
        render json: payload.to_json, status: :ok
      end
    end
  end

  def diff_entries # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)
    return head :bad_request unless params[:paths].present?

    unsafe_params = indifferent_params

    parsed_params = PullRequests::PageData::Diffs::Contents::Params.new(
      paths: unsafe_params[:paths],
      context: unsafe_params[:ctx],
    )
    paths = parsed_params.paths
    context_lines = parsed_params.context_lines

    pull = @pull_request
    pull_comparison = calculate_comparison(pull, unsafe_params[:range], current_user)
    return render_404 unless pull_comparison

    limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
      repository: current_repository,
      user: current_user,
    )

    diff_contents_data = PullRequests::PageData::Diffs::Contents::Loader.load(
      context_lines:,
      current_user: current_user,
      diff: T.must(pull_comparison).diff,
      ignore_whitespace: ignore_whitespace?(pull, params, current_user, logged_in?),
      paths:,
      pull_request: @pull_request,
      repository: pull.head_repository,
      limit_config: limit_config,
      timeout: request_time_left / 2,
      top_only: false,
      # TODO send from frontend to avoid db query
      viewed_files: PullRequestUserReviews.new(pull, current_user),
    )

    json = PullRequests::PageData::Diffs::Contents::Payload.call(diff_contents_data).as_json

    respond_to do |format|
      format.json do
        render json:, status: :ok
      end
    end
  end

  # Fetches lines for diff entry at given path, including injected context lines if present in line ranges provided
  def diff_entry_lines # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)

    unsafe_params = indifferent_params
    path = unsafe_params[:path]
    return head :bad_request unless path.present?

    pull = @pull_request
    pull_comparison = calculate_comparison(pull, unsafe_params[:range], current_user)
    return render_404 unless pull_comparison

    context_lines = nil
    if params[:context_line_ranges].present?
      begin
        line_ranges_maps = params[:context_line_ranges].map { |range_string| JSON.parse(range_string) }

        line_ranges_array = line_ranges_maps.map do |range_map|
          Range.new(range_map["start"], range_map["end"])
        end
        context_lines = { path => line_ranges_array }
      rescue JSON::ParserError => e
        GitHub.logger.warn "Invalid JSON in context_line_ranges for pull request #{@pull_request.id}: #{e.message}"
        return render json: { error: "Invalid JSON format in context_line_ranges parameter" }, status: :bad_request
      rescue KeyError => e
        GitHub.logger.warn "Missing key in context_line_ranges for pull request #{@pull_request.id}: #{e.message}"
        return render json: { error: "Missing key in context_line_ranges parameter: #{e.message}" }, status: :bad_request
      rescue TypeError => e
        GitHub.logger.warn "Invalid type in context_line_ranges for pull request #{@pull_request.id}: #{e.message}"
        return render json: { error: "Invalid type in context_line_ranges parameter: #{e.message}" }, status: :bad_request
      rescue ArgumentError => e
        GitHub.logger.warn "Invalid range value in context_line_ranges for pull request #{@pull_request.id}: #{e.message}"
        return render json: { error: "Invalid range value in context_line_ranges parameter: #{e.message}" }, status: :bad_request
      end
    end

    limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
      repository: current_repository,
      user: current_user,
    )

    begin
      diff_contents_data = PullRequests::PageData::Diffs::Contents::Loader.load(
        context_lines: context_lines,
        current_user: current_user,
        diff: T.must(pull_comparison).diff,
        rich_diff_strategy: PullRequests::PageData::Diffs::Contents::Loader::RichDiffStrategy::Skip, # don't load rich diff when fetching lines
        ignore_whitespace: ignore_whitespace?(pull, params, current_user, logged_in?),
        paths: [path],
        pull_request: @pull_request,
        repository: pull.head_repository,
        limit_config: limit_config,
        timeout: request_time_left / 2,
        # TODO error handling for large diffs.
        top_only: false,
        show_hidden: true,
        viewed_files: PullRequestUserReviews.new(pull, current_user),
      )

      diff_contents_payload = PullRequests::PageData::Diffs::Contents::Payload.call(diff_contents_data).as_json
    rescue GitRPC::Error => e
      GitHub.logger.error "GitRPC error loading diff for pull request #{@pull_request.id}, path '#{path}': #{e.message}"
      Failbot.report(e, pull_request_id: @pull_request.id, path: path)
      return render json: { error: "Failed to load diff data due to a Git service error." }, status: :internal_server_error
    rescue => e
      GitHub.logger.error "Unexpected error loading diff for pull request #{@pull_request.id}, path '#{path}': #{e.message}"
      Failbot.report(e, pull_request_id: @pull_request.id, path: path)
      return render json: { error: "An unexpected error occurred while loading diff data." }, status: :internal_server_error
    end

    diff_entry_data = diff_contents_payload.first

    if diff_entry_data.nil?
      GitHub.logger.warn "Invalid path '#{path}' requested for pull request #{@pull_request.id} - path not found in diff"
      return render json: { error: "Invalid path: '#{path}' not found in diff" }, status: :bad_request
    end

    diff_entry_lines = diff_entry_data["diffLines"]

    respond_to do |format|
      format.json do
        render json: { diffEntryLines: diff_entry_lines }, status: :ok
      end
    end
  end

  def diffstat # rubocop:todo GitHub/UseRestfulActions
    summary_diff = @pull_request.historical_comparison.async_diff(summary: true).sync

    begin
      lines_added = summary_diff.additions
      lines_deleted = summary_diff.deletions
      lines_changed = summary_diff.changes
    rescue GitRPC::Error => error
      Failbot.report error
    end

    render json: {
      diffstat: {
        linesAdded: lines_added,
        linesDeleted: lines_deleted,
        linesChanged: lines_changed,
      }
    }
  end

  def copilot_diff_chat # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)
    return head :forbidden unless helpers.copilot_chat_enabled_for_current_user?

    base_oid = params[:base_oid]
    head_oid = params[:head_oid]

    copilot_diff_chat_data = PullRequests::PageData::CopilotDiffChat::Loader.load(base_oid: base_oid, head_oid: head_oid, pull_request: @pull_request)

    payload = PullRequests::PageData::CopilotDiffChat::Payload.call(copilot_diff_chat_data)

    respond_to do |format|
      format.json do
        render json: payload.to_json, status: :ok
      end
    end
  end

  def copilot_code_review_show_upsell # rubocop:todo GitHub/UseRestfulActions
    ccr_access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository)
    copilot_user = ::Copilot::Public::User.new(T.must(current_user))
    copilot_provider = copilot_user.copilot_provider
    dismiss_key = "DismissCopilotCodeReviewUpsell:V1:#{T.must(current_user).id}"
    banner_dismissed = Users::Kv.store.exists(dismiss_key).value { false }

    upsell_plan = nil
    billing_url = nil
    policy_url = nil
    upsell_url = nil

    ccr_copilot_max_enabled = T.must(current_user).feature_flag_enabled?(:ccr_ux_max_sku, default: false)

    if copilot_user.copilot_provider.is_a?(::Copilot::Business)
      billing_url = settings_billing_enterprise_path(copilot_provider)
      policy_url = settings_org_copilot_policies_url(copilot_provider)
      upsell_plan = "Enterprise" unless copilot_user.copilot_plan == "enterprise"
    elsif copilot_user.copilot_provider.is_a?(::Copilot::Organization)
      billing_url = settings_org_billing_url(copilot_provider)
      policy_url = settings_org_copilot_policies_url(copilot_provider)
      upsell_url = features_copilot_url unless copilot_user.copilot_plan == "enterprise"
      upsell_plan = "Enterprise" unless copilot_user.copilot_plan == "enterprise"
    else
      billing_url = settings_user_billing_path
      policy_url = "/settings/copilot"
      upsell_url = features_copilot_url unless ccr_copilot_max_enabled ? copilot_user.has_max_access? : copilot_user.has_pro_plus_access?
      upsell_plan = "Pro+" if copilot_user.has_pro_access?
      upsell_plan = "Max" if copilot_user.has_pro_plus_access? && ccr_copilot_max_enabled
    end

    payload = {
      plan: copilot_user.copilot_plan,
      upsellPlan: upsell_plan,
      overagesVisible: user_feature_enabled?(:copilot_overages),
      overagesEnabled: copilot_user.overages_enabled?,
      isAdmin: !!copilot_user.copilot_provider&.admins&.exists?(T.must(current_user).id),
      quotaReset: {
        date: ccr_access.quota_reset_date.strftime("%b %-d, %Y"),
        dateTime: ccr_access.quota_reset_date.strftime("%B %-d, %Y, at %l:%M %P"),
      },
      bannerDismissKey: dismiss_key,
      bannerDismissed: banner_dismissed,
      urls: {
        docs: Copilot::COPILOT_PREMIUM_REQUESTS_DOCS,
        billing: billing_url,
        policy: policy_url,
        upsell: upsell_url,
      }
    }

    render json: payload.to_json, status: :ok
  end

  def copilot_code_review_dismiss_upsell # rubocop:todo GitHub/UseRestfulActions
    return head :bad_request if !params[:key].present?
    quota_reset_date = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository).quota_reset_date
    Users::Kv.store.set(params[:key], "true", expires: quota_reset_date.to_time)

    head :created
  end

  def copilot_assisted_code_review_dismiss_upsell # rubocop:todo GitHub/UseRestfulActions
    PullRequests::Copilot::CodeReviewUpsell.new(
      actor: T.must(current_user),
      current_repository: current_repository,
    ).dismiss!

    head :created
  end

  # This action is for applications that need to get an initial dataset to render a PR's comparison view with the DiffComparisonViewer.
  # We return the same data in the `#files` action where we render the Files React app currently.
  def base_comparison_info # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)

    range = params[:range]
    mode = params[:mode]
    single_file_mode = mode == "single"

    begin
      pull_comparison = calculate_comparison(@pull_request, range, current_user)

      limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
        repository: current_repository,
        user: current_user,
        single_file_mode: single_file_mode,
      )

      files_data = PullRequests::PageData::Files::Loader.load(
        comparison: T.must(pull_comparison),
        current_user: current_user,
        file_filter: {
          selected_file_extensions: params[FILE_TYPE_FILTER_PARAM],
          show_deleted_files: !deleted_files_hidden?,
          show_only_manifest_files: manifest_files_active?,
          show_only_owned_files: only_owned_by_active?,
          show_vendored_files: !vendored_files_hidden?,
          show_viewed_files: !viewed_files_hidden?,
        },
        ignore_whitespace: ignore_whitespace?(@pull_request, params, current_user, logged_in?),
        include_codeowners: only_owned_by_active?,
        timeout: request_time_left / 2,
        pull_request: @pull_request,
        cap_filter: cap_filter,
        user_session: user_session,
        limit_config: limit_config,
        short_path: params[:short_path]
      )

      payload = PullRequests::PageData::Files::Payload.call(files_data)

      render json: payload.as_json, status: :ok
    rescue TypeError, PullRequestsController::FilesUnavailable, GitRPC::ObjectMissing => error
      Failbot.report error
      render status: :internal_server_error, json: { error: "Sorry, this diff is unavailable." }
    rescue PullRequestsController::BadRange, PullRequestsController::NonCanonicalRange, PullRequestsController::OrphanCommit => error
      Failbot.report error
      render status: :not_found, json: { error: "Commit range not found." }
    rescue GitHub::Diff::Parser::UnrecognizedText
      render status: :not_found, json: { error: "This diff could not be parsed." }
    end
  end

  def thread_previews # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)

    limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
      repository: current_repository,
      user: current_user,
    )

    viewed_files_count = PullRequests::PageData::ThreadPreviews::Loader.load(
      cap_filter: cap_filter,
      current_user: current_user,
      pull_request: @pull_request,
      limit_config: limit_config,
    )

    payload = PullRequests::PageData::ThreadPreviews::Payload.call(viewed_files_count)

    render json: payload.to_json, status: :ok
  end

  # Used for profiling file tree in isolation
  def file_tree # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)

    pull_comparison = calculate_comparison(@pull_request, params[:range], current_user)
    return render_404 unless pull_comparison

    limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
      repository: current_repository,
      user: current_user,
    )

    file_tree_data = PullRequests::PageData::Files::FileTree::Loader.load(
      comparison: pull_comparison,
      current_user: current_user,
      pull_request: @pull_request,
      cap_filter: cap_filter,
      user_session: user_session,
      end_commit_oid: pull_comparison.end_commit.oid,
      limit_config: limit_config,
    )

    payload = PullRequests::PageData::Files::FileTree::Payload.call(file_tree_data)

    render json: payload.to_json, status: 200
  end

  def codeowners # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)

    pull_comparison = calculate_comparison(@pull_request, params[:range], current_user)
    return render_404 unless pull_comparison

    paths = pull_comparison.changed_filepaths

    codeowners_data = PullRequests::PageData::Codeowners::Loader.load(
      viewer: current_user,
      paths: paths,
      refname: pull_comparison.diff.base_sha,
      repository: @pull_request.base_repository,
    )

    payload = PullRequests::PageData::Codeowners::Payload.call(codeowners_data)
    render json: payload.to_json, status: :ok
  end

  def rich_diff # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)

    unsafe_params = indifferent_params
    path = unsafe_params[:path]
    return head :bad_request unless path.present?

    pull = @pull_request
    pull_comparison = calculate_comparison(pull, unsafe_params[:range], current_user)
    return render_404 unless pull_comparison

    limit_config = PullRequests::PageData::Files::PageLimitConfig.new(
      repository: current_repository,
      user: current_user,
    )

    diff_contents_data = PullRequests::PageData::Diffs::Contents::Loader.load(
      current_user: current_user,
      diff: T.must(pull_comparison).diff,
      highlighting_strategy: PullRequests::PageData::Diffs::Contents::Loader::HighlightStrategy::None, # skip syntax highlighting for rich diff
      rich_diff_strategy: PullRequests::PageData::Diffs::Contents::Loader::RichDiffStrategy::Full, # force loading of rich diff
      ignore_whitespace: ignore_whitespace?(pull, params, current_user, logged_in?),
      paths: [path],
      pull_request: @pull_request,
      repository: pull.head_repository,
      limit_config: limit_config,
      timeout: request_time_left / 2,
      top_only: false,
      show_hidden: true,
      viewed_files: PullRequestUserReviews.new(pull, current_user),
    )

    diff_entry_data = diff_contents_data.diff_entries.first
    render_404 unless diff_entry_data

    rich_diff_payload = PullRequests::PageData::Diffs::RichDiff::Payload.call(T.must(diff_entry_data).rich_diff)
    render json: rich_diff_payload.as_json, status: :ok
  end

  def change_groups # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless @pull_request
    return render_404 if @pull_request.hide_from_user?(current_user)

    change_groups_data = PullRequests::PageData::ChangeGroupGeneration::Loader.load(
      comparison: @pull_request.pull_comparison,
      current_user: current_user,
      pull_request: @pull_request,
    )

    payload = PullRequests::PageData::ChangeGroupGeneration::Payload.call(change_groups_data)

    render json: payload.to_json, status: :ok
  end

  private

  def indifferent_params
    params_value = params
    if params_value.is_a?(ActionController::Parameters)
      params_value.permit!.to_h.with_indifferent_access
    else
      params_value.to_h.with_indifferent_access
    end
  end

  sig { void }
  def load_pull_request
    @pull_request = PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
    render_404 if @pull_request.nil?
    @pull_request
  end

  sig { returns(Integer) }
  memoize def avatar_size
    params[:avatar_size] ? params[:avatar_size].to_i : PullRequests::PageData::StatusChecksSerializer::AVATAR_DEFAULT_SIZE
  end

  def render_rate_limited_response
    render status: :too_many_requests, json: { error: RATE_LIMIT_REACHED }
  end

  sig { returns(T::Hash[Symbol, String]) }
  memoize def title_params
    { title: params.fetch(:title, "") }
  end

  sig { returns(T::Hash[Symbol, String]) }
  memoize def change_base_params
    { new_base_binary: params.fetch(:new_base_binary, "") }
  end

  sig { void }
  def require_xhr
    head(:not_acceptable) unless request&.xhr? || current_user&.employee?
  end

  # Override in controller to allowlist routes for advisory workspace repositories.
  def route_supports_advisory_workspaces?
    %w[
    change_base
    code_button
    codeowners
    commits
    diff_entries
    diff_entry_lines
    diff_entry_with_context
    diffstat
    header
    merge_box
    status_checks
    tab_counts
    thread_previews
    update_title
    viewed_files_count
    ].include?(action_name)
  end
end
