# typed: false
# frozen_string_literal: true

class DiffsController < GitContentController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    only: [:show, :diff_lines]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Notify, # delete once we move code quality findings to a proper db table
    optional: true, only: [:index, :show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:unchanged_files_with_annotations]

  MAX_ENTRIES_BATCH_SIZE = ::GitHub::Diff::DEFAULT_MAX_FILES

  include ApplicationController::VerifiedFetchDependency
  include DiffHelper
  include Commit::ReactDiffLinesHelper
  include Commit::ReactPayloadDataDependency
  include ControllerMethods::Commit
  include ControllerMethods::Diffs

  allow_verified_fetch only: [:diff_lines]

  javascript_bundle :diffs

  skip_before_action :try_to_expand_path

  BLOB_PATHS_LIMIT = 50

  def index
    return head :not_found unless valid_params?

    progressive_diff_load!

    diff.minimize_total_limits!

    @batched_file_list_view = ::Diff::BatchedFileListView.new(file_list_view,
      start_entry_index: params[:start_entry],
      already_shown_bytes: params[:bytes],
      already_shown_lines: params[:lines],
      max_entries_batch_size: MAX_ENTRIES_BATCH_SIZE,
    )
    @batched_file_list_view.prepare
    prepare_rendering(file_views)

    respond_to do |format|
      format.html do


        if file_views.any?
          render partial: "diff/diff_entries", locals: {
            sticky: params[:sticky] == "true",
            file_views: file_views,
            file_list_view: file_list_view,
            batched_file_list_view: batched_file_list_view,
            base_repository: base_repository,
            head_repository: head_repository,
          }
        else
          head :not_found
        end
      end
      format.json do
        diff_payload = build_file_diff_payload(file_list_view, batched_file_list_view.start_entry_index, current_user)
        render json: {
          extraDiffEntries: diff_payload.as_json(only: ALLOWED_DIFF_JSON_FIELDS),
          loadMore: batched_file_list_view.load_more?,
          asyncDiffLoadInfo: {
            startIndex: batched_file_list_view.next_start_entry_index,
            truncated: file_list_view.truncated?,
            byteCount: file_list_view.diffs.total_byte_count,
            lineShownCount: file_list_view.diffs.total_line_count,
          },
      }
      end
    end
  end

  def show
    return head :not_found unless valid_params?

    non_progressive_diff_load!

    diff.add_delta_index(params[:entry].to_i)
    diff.maximize_single_entry_limits!
    diff.load_diff

    diff_entry = diff.entries.first
    return head :not_found if diff_entry.nil?

    @file_view = ::Diff::FileView.new(
      diff: diff_entry,
      repository: repository,
      current_user: current_user,
      show_generated: true,
      show_deleted: true,
    )
    prepare_rendering([@file_view])

    skip_dependency_review = DependencyReview::ManifestLimitHelper.diff_too_large?(file_list_view)

    respond_to do |format|
      format.html do
        render partial: "diff/diff_entry", locals: {
          view: file_view,
          file_list_view: file_list_view,
          base_repository: base_repository,
          head_repository: head_repository,
          disable_render: false,
          source_toggle_selected: params[:source].present?,
          text_only: true,
          skip_dependency_review: skip_dependency_review,
        }
      end
    end
  end

  def diff_lines # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless valid_params?
    return head :not_found unless react_commit_enabled?

    non_progressive_diff_load!

    diff.add_delta_index(params[:entry].to_i)
    diff.maximize_single_entry_limits!
    diff.load_diff

    diff_entry = diff.entries.first
    return head :not_found if diff_entry.nil?

    @file_view = ::Diff::FileView.new(
      diff: diff_entry,
      repository: repository,
      current_user: current_user,
      show_generated: true,
      show_deleted: true,
    )
    prepare_diff_line_rendering([@file_view])

    highlighted_diff = SyntaxHighlightedDiff.new(file_list_view.repository)

    if use_styling_directives
      styling_directives = highlighted_diff.styling_directive(diff_entry)
    else
      shd = highlighted_diff.colorized_lines(diff_entry)
      if shd
        shd.each(&:freeze)
        shd.freeze
      end
    end

    diff_lines = build_diff_line_data(diff_entry, shd, styling_directives: styling_directives)

    respond_to do |format|
      format.json do
        render json: { diffLines: diff_lines }
      end
    end
  end

  def unchanged_files_with_annotations # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless valid_params_for_unchanged_files_with_annotations?

    blob_paths = DiffsController::truncate_non_diff_blobs(params[:blob_paths])

    @non_diff_blobs ||= GitHub.dogstats.time "checks.load_non_diff_blobs.time" do
      non_diff_blobs(blob_paths)
    end

    # No content to show to the user. Ideally we would return :no_content here
    # but the frontend interprets that as an error and we don't want to show an error
    # to the user in case this does happen.
    unless @non_diff_blobs.present?
      GitHub.dogstats.increment("checks.no_non_diff_blobs_present")
      return head :ok
    end

    GitHub.dogstats.count("checks.unchanged_files_with_annotations", @non_diff_blobs.length)

    annotations = DiffAnnotations.new(repository.annotations_for(
      sha: params[:sha2],
      filenames: @non_diff_blobs.pluck(:path),
      limit: CheckAnnotation::MAX_READ_LIMIT
    ))
    annotations.load_code_scanning_alerts(viewer: current_user, repository: repository)

    GitHub.dogstats.count("checks.annotations_in_unchanged_files", annotations.count)

    respond_to do |format|
      format.html do
        render partial: "diff/non_diff_entries", locals: {
          non_diff_blobs: @non_diff_blobs,
          repository: repository,
          pull_request: pull,
          annotations: annotations,
        }
      end
    end
  end

  def self.truncate_non_diff_blobs(blob_paths)
    if blob_paths.length > BLOB_PATHS_LIMIT
      GitHub.dogstats.count("checks.unchanged_files_with_annotations.above_limit", blob_paths.length)
      blob_paths = blob_paths.first(BLOB_PATHS_LIMIT)
    end
    blob_paths
  end

  private

  attr_reader :batched_file_list_view, :file_view, :progressive
  alias :progressive? :progressive

  def progressive_diff_load!
    @progressive = true
  end

  def non_progressive_diff_load!
    @progressive = false
  end

  def valid_params?
    valid_repositories? &&
      valid_sha_param?(:sha1) &&
      valid_sha_param?(:sha2) && params[:sha2].present? &&
      valid_sha_param?(:base_sha) &&
      valid_commit? &&
      valid_pull? &&
      valid_int_param?(:bytes) &&
      valid_int_param?(:lines)
  end

  def valid_params_for_unchanged_files_with_annotations?
    valid_params? &&
    params[:blob_paths].present? &&
    params[:blob_paths].is_a?(Array)
  end

  def valid_repositories?
    head_repository.present? && base_repository.present?
  end

  # Validates the provided parameter is a valid sha, or nil
  def valid_sha_param?(param_name)
    param = params[param_name]
    param.nil? || GitRPC::Util.valid_full_oid?(param)
  end

  # Validates specifically the commit parameter to ensure we are dealing with a real commit
  def valid_commit?
    return false unless valid_sha_param?(:commit)
    return commit.present? if params[:commit]
    true
  end

  # Ensures we are dealing with a real pull request
  def valid_pull?
    return true if params[:pull_number].nil?
    pull.present?
  end

  def valid_int_param?(param_name)
    return true if params[param_name].nil?
    return false unless params[param_name].respond_to?(:to_i)
    true
  end

  def is_range?
    commit.nil? && pull.nil?
  end

  def prepare_rendering(file_views)
    tree_entries = tree_entries_for(file_views)
    Promise.all(tree_entries.map(&:async_data)).sync
    file_views.each { |fv| fv.prepare_for_rendering! }

    content_file_views = file_views.select(&:has_content?)
    diff_entries = content_file_views.map(&:diff)
    highlight_diff(diff_entries)
    diff.record_diff_metrics(params: params, dogstats_request_tags: dogstats_request_tags + dogstats_staff_request_tags)

    content_tree_entries = content_file_views.map(&:diff_blob).reject(&:nil?)
    load_line_counts(content_tree_entries)
    load_attributes(content_tree_entries)

    preload_review_threads_and_comments
    # TODO: We need to stop relying on instance variables. A helper method would probably
    # be a bit better here, but could require expansive refactoring.

    comparison # load the comparison into its instance variable for DiffHelper in the view
  end

  def prepare_diff_line_rendering(file_views)
    tree_entries = tree_entries_for(file_views)
    Promise.all(tree_entries.map(&:async_data)).sync
    file_views.each { |fv| fv.prepare_for_rendering! }

    content_file_views = file_views.select(&:has_content?)
    diff_entries = content_file_views.map(&:diff)
    highlight_diff(diff_entries)
    diff.record_diff_metrics(params: params, dogstats_request_tags: dogstats_request_tags + dogstats_staff_request_tags)

    content_tree_entries = content_file_views.map(&:diff_blob).reject(&:nil?)
    load_line_counts(content_tree_entries)
    load_attributes(content_tree_entries)
  end

  def comparison # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @comparison if defined?(@comparison)

    base         = "#{params[:base_user]}:#{params[:sha1]}"
    head         = "#{params[:head_user]}:#{params[:sha2]}"
    commit_limit = 0 # we are not interested in commits

    @comparison  = repository.comparison(base, head, commit_limit, pull)
  end

  # Private: Warm up syntax highlighted diff cache for the diff to render
  def highlight_diff(diff_entries)
    shd = SyntaxHighlightedDiff.new(file_list_view.repository)

    if use_styling_directives
      shd.highlight_with_styled_directives!(diff_entries)
    else
      shd.highlight!(diff_entries, attributes_commit_oid: file_list_view.attributes_commit_oid)
    end
  end

  # Private: Preload line counts for the tree entries of all file views. This is
  # necessary for rendering the expander UI.
  def load_line_counts(tree_entries)
    TreeEntry.load_line_counts!(file_list_view.repository, tree_entries)
  end

  # Private: Preload attributes for the tree entries of all file views. This is
  # necessary for rendering the expander UI.
  def load_attributes(tree_entries)
    TreeEntry.load_attributes!(tree_entries, file_list_view.attributes_commit_oid)
  end

  def diff_options
    {
      ignore_whitespace: ignore_whitespace?,
      use_summary:       true,
      timeout:           (request_time_left / 3),
      max_files:         MAX_ENTRIES_BATCH_SIZE,

      base_sha:          params[:base_sha],
      context_lines:     end_commit&.annotations&.line_ranges,
      base_repository:   base_repository,
      head_repository:   head_repository,
    }
  end

  def diff # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @diff if defined?(@diff)

    @diff = ::GitHub::Diff.new(repository, params[:sha1], params[:sha2], diff_options)
  end

  def file_list_view # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @file_list_view if defined?(@file_list_view)

    @file_list_view = ::Diff::FileListView.new(
      diffs: diff,
      params: params,
      current_user: current_user,
      commit: commit,
      pull: pull,
      pull_comparison: pull_comparison,
      commentable: params[:commentable] ? true : false,
      highlight: false, # already happening in the controller
      progressive: progressive?,
      number_offset: params[:start_entry].to_i,
    )
  end

  def file_views
    batched_file_list_view.file_views
  end

  def tree_entries_for(file_views)
    file_views
      .map { |file_view| file_view.diff_blob unless file_view.diff.binary? || file_view.diff.truncated? }
      .reject { |tree_entry| tree_entry.nil? || tree_entry.oid.nil? }
  end

  def repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @repository if defined?(@repository)

    @repository = current_repository.tap do |repo|
      repo.extend_rpc_alternates(base_repository, head_repository)
    end
  end

  def base_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @base_repository if defined?(@base_repository)
    @base_repository = fork_repository_for_user(params[:base_user])
  end

  def head_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @head_repository if defined?(@head_repository)
    @head_repository = fork_repository_for_user(params[:head_user])
  end

  def fork_repository_for_user(login)
    user = User.find_by_login(login)
    fork_repository = current_repository.find_fork_in_network_for_user(user)

    fork_repository || current_repository
  end

  def commit # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @commit if defined?(@commit)
    return unless params[:commit]

    @commit = begin
                repository.commits.find(params[:commit])
              rescue GitRPC::ObjectMissing
                nil
              end
  end

  def end_commit # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @end_commit if defined?(@end_commit)
    return unless params[:sha2]

    @end_commit = begin
      repository.commits.find(params[:sha2])
    rescue GitRPC::ObjectMissing
      nil
    end
  end

  def pull # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @pull if defined?(@pull)
    return unless params[:pull_number]

    @pull = repository.issues.find_by_number(params[:pull_number].to_i).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def pull_comparison # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @pull_comparison if defined?(@pull_comparison)
    return unless pull

    @pull_comparison = PullRequest::Comparison.find(
      pull:             pull,
      start_commit_oid: params[:sha1],
      end_commit_oid:   params[:sha2],
      base_commit_oid:  params[:base_sha],
    ).tap do |pull_comparison|
      if pull_comparison
        pull_comparison.diff_options = diff_options
        pull_comparison.diffs = diff
      end
    end
  end

  def threads # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @threads if defined?(@threads)

    @threads = file_list_view.threads
  end

  def preload_review_threads_and_comments
    return unless threads&.threads.present?

    # If we're rendering from the repository views outside of the pull request
    # context we won't have a pull object. In this case we only need to preload commit
    # comments since we only display review comments in the context of a pull request.
    return unless pull

    if pull.present?
      CodeScanning::ReviewCommentComponent.preload_review_comments(pull_request: pull)
    end

    review_threads = threads.threads.map(&:activerecord_pull_request_review_thread)
    GitHub::PrefillAssociations.prefill_associations(review_threads, :pull_request_review)
    review_threads.each { |thread| thread.current_comparison = pull_comparison }

    PullRequests::ReviewThreadComponent.preload_review_threads(review_threads: review_threads, viewer: current_user, pull_request: pull)

    review_comments = review_threads.map do |thread|
      page_info = thread.prelude_paginated_review_comments_for(current_user, PullRequests::ReviewThreadBodyComponent.pagination_params)
      review_comments = page_info[:first_group]
      review_comments += page_info[:last_group] if page_info[:last_group]
      review_comments
    end.flatten
    GitHub::PrefillAssociations.prefill_associations(review_comments, :repository, available_records: [current_repository])

    PullRequests::ReviewCommentComponent.preload_review_comments(
      review_comments: review_comments,
      reviews: review_threads.map(&:pull_request_review),
      pull_request: pull,
      viewer: current_user,
      cap_filter: cap_filter
    )
  end

  def non_diff_blobs(blob_paths)
    GitHub.dogstats.count("checks.load_non_diff_blobs.count", blob_paths.length)
    blob_paths_with_commit = blob_paths.map do |path|
      [params[:sha2], path]
    end

    blob_oids = repository.rpc.read_blob_oids(blob_paths_with_commit, skip_bad: true)

    # Mapping paths to oids to look them up later
    # Example: {"954ff693472edee57729124895122b7d4fbce800"=>"aquaman.txt"}
    paths_by_oid = Hash[blob_oids.zip(blob_paths)]

    raw_blobs = repository.read_objects(
      blob_oids.select(&:present?), :blob)
    raw_blobs.map do |raw_blob|
      path = paths_by_oid[raw_blob["oid"]]
      TreeEntry.new(repository, raw_blob.merge("path" => path))
    end
  end

  def route_supports_advisory_workspaces?
    true
  end

  def use_styling_directives
    FeatureFlag.vexi.enabled?(:css_custom_highlighting, current_user, default: false)
  end
end
