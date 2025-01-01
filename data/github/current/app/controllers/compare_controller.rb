# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/RailsControllerRenderLiteral

class CompareController < GitContentController
  map_to_service :repos # rubocop:todo GitHub/MapToService

  include CompareHelper, ControllerMethods::Diffs
  include ApplicationController::PartialRenderWithLayoutDependency

  layout "repository"
  javascript_bundle :diffs
  javascript_bundle :repositories

  skip_before_action :try_to_expand_path
  before_action :check_for_empty_repository
  before_action :clean_params

  around_action :record_stats, only: [:show, :file_list, :commit_list, :branch_list, :repository_list]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    optional: true, only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Permissions,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:tag_list]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:branch_list]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    only: [:branch_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    only: [:file_list]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    optional: true,
    only: [:file_list]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations, # Had to add this to handle EMU users
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    only: [:repository_list]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    optional: true, only: [:repository_list]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:pr_templates]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    optional: true, only: [:pr_templates]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Permissions,
    optional: false, only: [:commit_list]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Notify,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    optional: true, only: [:commit_list]

  TAGS_LIMIT = 100

  param_encoding :tag_list, :q, "ASCII-8BIT"

  # Landing page for "what do I want to compare?" — starting point for branch
  # discussions and pull requests as well.
  def new
    head = current_repository.default_branch
    base = current_repository.base_branch(head, current_user)
    if base != head
      redirect_to compare_path(current_repository, "#{base}...#{head}")
    else
      # Prime up the range editor with an empty Comparison
      @comparison = current_repository.comparison(head, head)
      render "compare/new"
    end
  end

  param_encoding :show, :range, "ASCII-8BIT"
  # A comparison without a discussion, kind of like a branch discussion in
  # waiting.
  def show
    GitHub.tracer.in_span("compare_controller#show", attributes: { "gh.repo.id" => current_repository.id }, kind: :internal) do |span|
      unsafe_params = params.to_unsafe_h.with_indifferent_access

      if unsafe_params[:range].blank?
        redirect_to range: current_repository.default_branch
        return
      end

      #TODO - look into reducing this limit, with a load more option
      @comparison = GitHub::Comparison.from_range_or_ref(
        current_repository,
        unsafe_params[:range],
        limit: 250,
        user: current_user,
      )

      stats.entity = @comparison

      direct_compare = @comparison.direct_compare?

      # monitoring feature usage for direct comparison for rollout period.
      GitHub.dogstats.increment("compare.direct") if direct_compare
      span.set_attribute("gh.pull_request.comparison.direct", direct_compare)

      # Attempt to distinguish a compare view for an existing ref named
      # something.patch or something.diff from the patch/diff view for a
      # ref named something.
      head_ref_valid = @comparison.head_repo && @comparison.head_repo.refs.exist?(@comparison.head_ref)
      span.set_attribute("gh.pull_request.head_ref.valid", head_ref_valid.to_s)

      if @comparison.head.end_with?(".patch") && !head_ref_valid
        @comparison = GitHub::Comparison.deprecated_build(
          @comparison.repo, @comparison.base, @comparison.head.chomp(".patch"), limit: 250
        )
        return render_patch
      elsif @comparison.head.end_with?(".diff") && !head_ref_valid
        @comparison = GitHub::Comparison.deprecated_build(
          @comparison.repo, @comparison.base, @comparison.head.chomp(".diff"), limit: 250
        )
        return render_diff
      end

      if ref = unsafe_params[:new_compare_ref]
        if unsafe_params[:new_compare_type] == "base"
          safe_redirect_to base_ref_comparison_path(@comparison, ref)
        else
          safe_redirect_to head_ref_comparison_path(@comparison, ref)
        end
        return
      end

      # Since comparisons can be cross repository, we need to ensure you can't
      # see things you don't have permission to.
      comparison_viewable = @comparison.viewable_by?(current_user)
      span.set_attribute("gh.pull_request.comparison.viewable", comparison_viewable)
      if !comparison_viewable

        # make a new in-repo comparison for the range_editor partial to not act weird
        @comparison = current_repository.comparison(@comparison.base_ref, @comparison.head_ref, limit = 250)

        return render "compare/invalid", status: 404
      end

      if head_ref_unsafe_for_comparison?
        return render "compare/invalid", status: 404
      end

      if @comparison.base_repo && @comparison.base_repo != current_repository && !current_repository.advisory_workspace?
        flash.keep

        range = "#{@comparison.base_ref}...#{@comparison.head_user_login}:#{@comparison.head_repo.name}:#{@comparison.head_ref}"

        return redirect_to(compare_path(@comparison.base_repo, range, expand: unsafe_params[:expand].present?))
      end

      GitHub.tracer.in_span("compare_controller#show.existing_pulls", kind: :internal) do |_span|
        existing_pull_conditions = {
          base_repository_id: @comparison.base_repo.id,
          head_repository_id: @comparison.head_repo.id,
          base_ref: Git::Ref.safe_ref_name(ref_names: @comparison.base_ref),
          head_ref: Git::Ref.safe_ref_name(ref_names: @comparison.head_ref),
        }
        existing_pull_scope = if @comparison.repo.spammy?
          @comparison.repo.pull_requests.none
        else
          @comparison.repo.pull_requests.filter_spam_for(current_user, show_spam_to_staff: false)
        end

        # There can only be one open PR for a given comparison.
        # This query explicitly queries against the `issues.repository_id` to make the query more performant
        # See the analysis in https://github.com/github/github/pull/165037
        existing_open_pull = existing_pull_scope \
          .open_pulls
          .where(
            pull_requests: existing_pull_conditions,
            issues: { repository: @comparison.repo }
          ).first

        # Pull requests that have been closed without merging
        # but still match the tip of the head branch.
        existing_closed_pulls = existing_pull_scope \
          .includes(:issue)
          .where(head_sha: @comparison.head_sha, merged_at: nil, issues: { state: "closed" })
          .order("pull_requests.id DESC")
          .limit((existing_open_pull.nil? ? 5 : 4))
          .to_a

        @existing_pulls = [existing_open_pull, *existing_closed_pulls].compact
      end

      @comparison.set_diff_options(
        top_only:          true,
        use_summary:       true,
        ignore_whitespace: %w[1 true].include?(params[:w]),
        timeout:           request_time_left / 2,
      )

      GitHub.tracer.in_span("compare_controller#show.prepare_comparison", kind: :internal) do |_span|
        # This will copy over missing commits from the base repo into the head repo
        # to make comparisons work across networks for advisory workspaces.
        if current_repository.advisory_workspace? && !@comparison.valid?
          current_repository.fetch_workspace_base_ref!(base_sha: @comparison.base_sha, origin_for_stats: "compare_show")
        end
      end

      span.set_attribute("gh.pull_request.comparison.valid", @comparison.valid?)

      if @comparison.valid?
        # load diff
        GitHub.tracer.in_span("compare_controller#show.diff.load.initial", kind: :internal) do |_span|
          GitHub.dogstats.time("diff.load.initial", tags: dogstats_request_tags) do
            @comparison.init_diffs.apply_auto_load_single_entry_limits!
            @comparison.diffs
          end
        end
      end

      if !@comparison.valid? || @comparison.diffs.missing_commits?
        return render "compare/invalid", status: 404
      end

      # this makes links in the nav go to the right place ...
      unsafe_params[:name] = @comparison.head_ref

      if logged_in?
        GitHub.tracer.in_span("compare_controller#show.build_pull_request", kind: :internal) do |_span|
          @pull = @comparison.build_pull_request(user: current_user)
          @pull.build_issue repository: @pull.repository

          if flash[:pull_request]
            title_from_flash = flash[:pull_request]["title"]
            body_from_flash = flash[:pull_request]["body"]
          end

          if unsafe_params[:pull_request].is_a?(Hash)
            unsafe_params[:title] ||= unsafe_params[:pull_request][:title]
            unsafe_params[:body] ||= unsafe_params[:pull_request][:body]
          end

          fields = PrefilledIssueFields.new(
            params: unsafe_params,
            repository: current_repository,
            user: current_user,
          )

          @pull.body_template_name = fields.template
          @pull.issue.title = title_from_flash || fields.title
          @pull.issue.body = body_from_flash || fields.body
          @pull.issue.labels = fields.labels
          @pull.issue.projects = fields.projects
          @pull.issue.milestone = fields.milestone
          @pull.issue.assignees = fields.assignees

          @pull.issue.title = @pull.default_title if @pull.issue.title.blank?
          @pull.issue.body = @pull.default_body if @pull.issue.body.blank?

          @is_pull_request_draft = PullRequests::UserSettings.new(current_user, current_repository).default_pull_requests_to_draft?
        end
      end

      GitHub.tracer.in_span("compare_controller#show.prefill_verified_signature", kind: :internal) do |_span|
        Commit.prefill_verified_signature(@comparison.commits, @comparison.head_repo)
      end

      GitHub.dogstats.increment("compare.show.tabs", tags: ["tabs:#{render_tabs_on_compare?(@comparison)}"])

      locals = { is_pull_request_draft: !!@is_pull_request_draft }

      GitHub.tracer.in_span("compare_controller#show.render", kind: :internal) do |_span|
        GlobalInstrumenter.instrument("pull_request.user_action",
          {
            user_id: current_user&.id,
            repository_id: current_repository&.id,
            category: "compare_show",
            action: "show",
            data: @comparison.click_tracking_attributes
          }
        )
        stats.record_distribution("render_content") do
          render "compare/show", locals: locals
        end
      end
    end
  end

  rescue_from_timeout only: [:show] do |_boom|
    T.bind(self, CompareController)

    # TODO this isn't quite right with regard to the .patch/.diff branch name
    # differentiation that takes place in #show.
    range = params[:range].sub(/\.(?:diff|patch)\z/, "")
    @comparison = GitHub::Comparison.from_range_or_ref(current_repository, range, limit: 250, user: current_user)
    GitHub.dogstats.increment("compare.show.rescued_timeout", tags: ["repo:#{repo_stats_key}", "branch:#{branch_stats_key}"])

    return render_404 unless @comparison.viewable_by?(current_user)

    render "compare/timeout"
  end

  def repository_list # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless params[:type]

    range = params[:range] || current_repository.default_branch
    # light validity check before trying to build comparison from range
    return render_404 unless range.is_a?(String)

    comparison = GitHub::Comparison.from_range_or_ref(current_repository, range, limit: 250, user: current_user)
    stats.entity = comparison

    return render_404 unless comparison.viewable_by?(current_user)

    respond_to do |format|
      format.html do
        stats.record_distribution("render_repository_list") do
          render partial: "compare/repository_suggester_content", layout: partial_fragment_layout, locals: {
            comparison: comparison,
            type: params[:type].to_sym,
            selected: params[:selected],
            expand: params[:expand].present?,
          }
        end
      end
    end
  end

  def pr_templates # rubocop:todo GitHub/UseRestfulActions
    range = params[:range] || current_repository.default_branch
    comparison = GitHub::Comparison.from_range_or_ref(current_repository, range, limit: 250, user: current_user)

    return render_404 unless comparison.viewable_by?(current_user)

    respond_to do |format|
      format.html do
        render Compare::PullRequestTemplateListComponent.new(current_repository: current_repository, range: range, current_user: current_user, comparison: comparison), layout: component_fragment_layout
      end
    end
  end

  def file_list # rubocop:todo GitHub/UseRestfulActions
    range = params[:range] || current_repository.default_branch
    @comparison = GitHub::Comparison.from_range_or_ref(current_repository, range, limit: 250, user: current_user)

    @comparison.set_diff_options(
      top_only:          true,
      use_summary:       true,
      ignore_whitespace: %w[1 true].include?(params[:w]),
    )

    return render_404 unless @comparison.viewable_by?(current_user)

    diffs = @comparison.diffs
    stats.entity = @comparison

    respond_to do |format|
      format.html do
        stats.record_distribution("render_files_list") do
          render partial: "compare/files_changed", layout: false, locals: {
            diffs: diffs
          }
        end
      end
    end
  end

  def commit_list # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless range = params[:range]

    @comparison = GitHub::Comparison.from_range_or_ref(current_repository, range, user: current_user)
    stats.entity = @comparison

    return render_404 unless @comparison.viewable_by?(current_user)

    respond_to do |format|
      format.html do
        stats.record_distribution("render_commits_list") do
          render Compare::CommitsListComponent.new(comparison: @comparison, page: params[:page] || 1, current_user: current_user), layout: false
        end
      end
    end
  end

  def branch_list # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless params[:type]

    range = params[:range] || current_repository.default_branch
    comparison = GitHub::Comparison.from_range_or_ref(current_repository, range, limit: 250, user: current_user)
    stats.entity = comparison

    return render_404 unless comparison.viewable_by?(current_user)

    respond_to do |format|
      format.html do
        stats.record_distribution("render_branch_list") do
          render partial: "compare/commitish_suggester_content", layout: partial_fragment_layout, locals: {
            comparison: comparison,
            type: params[:type].to_sym,
            selected: params[:selected],
            expand: params[:expand].present?,
          }
        end
      end
    end
  end

  def tag_list # rubocop:todo GitHub/UseRestfulActions
    search_query = params[:q].to_s
    range = params[:range] || current_repository.default_branch
    comparison = GitHub::Comparison.from_range_or_ref(current_repository, range, limit: 250, user: current_user)
    target_repo = params[:type] == "head" ? comparison.head_repo : comparison.base_repo
    target_repo ||= comparison.repo

    return render_404 unless target_repo.pullable_by?(current_user)

    tags = target_repo.tags.substring_filter(substring: search_query, limit: TAGS_LIMIT)

    url_portion_callable = -> (tag) {
      if params[:type] == "base"
        base_ref_comparison_path(comparison, tag.name, expand: params[:expand].present?)
      else
        head_ref_comparison_path(comparison, tag.name, expand: params[:expand].present?)
      end
    }

    respond_to do |format|
      format.html_fragment do
        render "refs/tags",
          formats: :html,
          layout: false,
          locals: {
            url_portion_callable: url_portion_callable,
            current_tag_name: params[:tag_name],
            tags: tags,
          }
      end
    end
  end

  # Show this comparison as a .diff
  def diff # rubocop:todo GitHub/UseRestfulActions
    timeout_client_error do
      set_request_category! "raw"
      show
      render_diff
    end
  end

  # Show this comparison as a .patch
  def patch # rubocop:todo GitHub/UseRestfulActions
    timeout_client_error do
      set_request_category! "raw"
      show
      render_patch
    end
  end

  private

  # If it's empty, you can't compare nothin'
  def check_for_empty_repository
    if current_repository.empty?
      redirect_to current_repository
    end
  end

  # Internal: clean out the params hash
  #
  # sets blank params to nil
  def clean_params
    params[:quick_pull] = nil if params[:quick_pull] && params[:quick_pull].blank?
    true
  end

  # Internal: render a plain text .patch representation
  def render_patch
    return render "compare/invalid", status: 404 if !@comparison.valid?
    render plain: @comparison.to_patch if !performed?
  end

  # Internal: render a plain text .diff representation
  def render_diff
    return render "compare/invalid", status: 404 if !@comparison.valid?
    render plain: @comparison.to_diff if !performed?
  end

  def repo_stats_key
    if @comparison.base_repo == @comparison.head_repo
      "same_repo"
    elsif @comparison.base_repo == @comparison.head_repo.parent
      "from_parent"
    elsif @comparison.base_repo == @comparison.head_repo.network.root
      "from_network_root"
    elsif @comparison.head_repo == @comparison.base_repo.parent
      "to_parent"
    elsif @comparison.head_repo == @comparison.base_repo.network.root
      "to_network_root"
    else
      "other_repo"
    end
  end

  def branch_stats_key
    if @comparison.base_ref == @comparison.base_repo.default_branch
      if @comparison.head_ref == @comparison.head_repo.default_branch
        "both_default_branch"
      else
        "from_default_branch"
      end
    elsif @comparison.head_ref == @comparison.head_repo.default_branch
      "to_default_branch"
    else
      "other_branch"
    end
  end

  def route_supports_advisory_workspaces?
    true
  end

  # Override AbstractRepositoryController#defer_commit_badges? to
  # opt-in to deferred loading of commit signature badges.
  def defer_commit_badges?
    true
  end

  # Override AbstractRepositoryController#defer_status_check_rollups? to
  # opt-in to deferred loading of status check rollups
  def defer_status_check_rollups?
    true
  end

  # return true unless head_ref is "refs/heads/" prefixed
  # && a it is not referring to a branch that is such refs/heads/refs/head
  def head_ref_unsafe_for_comparison?
    @comparison.head_ref&.starts_with?("refs/heads/") &&
    !@comparison.head_repo.heads.find(@comparison.head_ref&.delete_prefix("refs/heads/"))
  end

  def record_stats
    stats.instrument_controller_action do
      yield
      response.successful?
    end
  end

  memoize def stats
    ::PageStats.new(
      controller_name: "compare",
      action_name: action_name,
      viewer: current_user,
      pjax: pjax?,
    )
  end

  helper_method :stats

end
