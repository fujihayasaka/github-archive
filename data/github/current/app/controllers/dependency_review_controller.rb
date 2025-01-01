# typed: true
# frozen_string_literal: true

class DependencyReviewController < AbstractRepositoryController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :login_required
  before_action :check_feature_is_enabled
  before_action :get_review_summary, only: :rich_diff

  after_action :instrument_rich_diff_view, only: :rich_diff

  include DependencyReview::VulnerabilityHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:rich_diff]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:rich_diff], optional: true

  # The defaults here should *only* be used as part of a `before_action` call.
  # rubocop:todo GitHub/UseRestfulActions
  def get_changed_manifests(base_sha: params[:base_sha], target_sha: params[:head_sha])
    return nil unless base_sha && target_sha

    diff = GitHub::Diff.new(current_repository, base_sha, target_sha)
    changed_paths = diff.summary.deltas.collect { |d| d.new_file.path }
    if changed_paths.any? { |path| DependencyManifestFile.recognized_path?(path: path) }
      manifest_changes(diff.summary.deltas)
    end
  end
  # rubocop:enable GitHub/UseRestfulActions

  def rich_diff # rubocop:todo GitHub/UseRestfulActions
    @pull_request = params[:pull_id] ? current_repository.pull_requests.find(params[:pull_id]) : nil
    @should_load_vulnerabilities = pull_request_and_sha_seem_legit(params[:base_sha], params[:head_sha])
    if @should_load_vulnerabilities
      @review_summary&.load_vulnerabilities(vulnerability_loader: self)
    end

    @review_summary&.sort_dependencies

    @manifest_path = params["manifest_path"]

    render DependencyReview::RichDiffComponent.new(
      review_summary: @review_summary,
      path: @manifest_path,
      error: @error,
    ), layout: false
  end

  private

  # Private: Check the current repository to see if we'd like to allow the request. We'll check:
  #   - Is dependency_graph_enabled?
  #   - Is current repository public
  #   - Does the current repository have advanced_security_enabled?
  #
  # Returns 404 for the request if the feature isn't enabled.
  def check_feature_is_enabled
    render_404 unless current_repository.dependency_review_enabled?
  end

  def pull_request_and_sha_seem_legit(base_sha, head_sha)
    return false unless @pull_request.present? && @pull_request.state == :open
    valid_commits = @pull_request.changed_commits.map(&:oid)
    valid_commits << @pull_request.base_sha
    valid_commits << @pull_request.merge_base
    valid_commits.include?(base_sha) && valid_commits.include?(head_sha)
  end

  def manifest_changes(deltas)
    base = []
    target = []
    deltas.each do |d|
      unless d.status == "A" # new file, so no old file is present
        base.push({ path: d.old_file.path.dup.force_encoding("UTF-8"), blob_id: d.old_file.oid })
      end
      unless d.status == "D" # deleted file, so no new file is present
        target.push({ path: d.new_file.path.dup.force_encoding("UTF-8"), blob_id: d.new_file.oid })
      end
    end
    { base: base, target: target }
  end

  def get_review_summary(base_sha: params[:base_sha], target_sha: params[:head_sha], changed_manifests: get_changed_manifests)
    begin
      @client = DependencyReview::SnapshotClient.new
      @snapshot_diff_encoded = GitHub.cache.fetch(review_summary_cache_key, force: Rails.env.development?) do
        @snapshot_diff = @client.get_snapshots_diff(
          repository_id: current_repository.id,
          base_sha: base_sha,
          target_sha: target_sha,
          repository_nwo: current_repository.nwo, # rubocop:todo GitHub/DoNotAllowNameWithOwner https://github.com/github/proxima/issues/1309
          repository_public: current_repository.public,
          repository_owner_id: current_repository.owner_id,
          limit_to_files: changed_manifests || { base: [], target: [] }
        )
        DependencyGraphAPI::V1::GetSnapshotsDiffResponse.encode(@snapshot_diff)
      end

      if @snapshot_diff.nil? && @snapshot_diff_encoded
        @snapshot_diff = DependencyGraphAPI::V1::GetSnapshotsDiffResponse.decode(@snapshot_diff_encoded)
      end

      return render_404 if @snapshot_diff.nil?

      apply_mock_data_as_needed(@snapshot_diff)
      @review_summary = DependencyReview::ReviewSummary.from_twirp(@snapshot_diff)
      dogstats_dependencies_counts(@review_summary)

      @review_summary
    rescue Faraday::TimeoutError => error
      GitHub.dogstats.increment("dependency_graph.dependency_review.timeouts_count")
      Failbot.report(error, app: "github-dependency-graph", rails_controller: "dependency_review")
      @error = {
        icon: "hourglass",
        body: "The dependency review for this pull request could not be retrieved in time."
      }
    rescue DependencyGraph::BaseTwirpClient::NotFoundError => error
      @error = {
        icon: "telescope",
        body: "Dependency review not found. Please try again or reach out if this problem persists."
      }
    rescue DependencyGraph::BaseTwirpClient::CircuitBrokenError => error
      Failbot.report(error, app: "github-dependency-graph", rails_controller: "dependency_review")
      @error = { body: "Too many failed dependency review requests have occurred in a short period of time." }
    rescue DependencyGraph::BaseTwirpClient::Error => error
      Failbot.report(error, app: "github-dependency-graph", rails_controller: "dependency_review")
      @error = { body: "An unexpected error occurred while retrieving the dependency review for this pull request." }
    end
  end

  def review_summary_cache_key
    now = Time.now.utc
    timestamp = [now.year, now.month, now.day, now.hour].join(":")

    ["dependency_review_summary_v2",
      current_repository.id,
      params[:base_sha],
      params[:head_sha],
      timestamp,
    ].join(":")
  end

  def apply_mock_data_as_needed(review_summary)
    if Rails.env.development?
      dependency_diff_add_octokit = DependencyGraphAPI::V1::GetSnapshotsDiffResponse::ManifestDiff::DependencyDiff.new(
        name: "octokit",
        repo_nwo: "octokit/octokit",
        target_version: "4.13.0",
        change_type: :DEPENDENCY_CHANGE_TYPE_ADDED,
        github_vulnerability_range_ids: [1],
        dependent_count: rand(0..4_500_000),
        license: "MIT",
        published_at: Time.new(rand(2014..2020), rand(1..12), rand(1..30)),
      )

      manifest_to_add_to = review_summary.changed_manifests.find { |m| m.type == :PACKAGE_MANAGER_RUBYGEMS }
      return if manifest_to_add_to.blank?

      manifest_to_add_to.dependencies.push(dependency_diff_add_octokit)
    end
  end

  # Private: Publish instrumentation about this request to Hydro.
  #
  def instrument_rich_diff_view
    return unless @review_summary.present? && @manifest_path.present?

    vulnerabilities_displayed = @review_summary.find_manifest(@manifest_path)&.vulnerable_dependencies&.count

    GlobalInstrumenter.instrument("dependency_graph.rich_diff.view", {
      actor: current_user,
      repo: current_repository,
      pull_request: @pull_request,
      path: @manifest_path,
      should_load_vulnerabilities: @should_load_vulnerabilities,
      filename: File.basename(@manifest_path),
      vulnerability_display_count: vulnerabilities_displayed,
    })
  end

  def dogstats_dependencies_counts(review_summary)
    GitHub.dogstats.count("dependency_graph.dependency_review.dependencies_count", review_summary.added_dependencies.count, tags: ["change_type:added"])
    GitHub.dogstats.count("dependency_graph.dependency_review.dependencies_count", review_summary.removed_dependencies.count, tags: ["change_type:removed"])
    GitHub.dogstats.count("dependency_graph.dependency_review.dependencies_count", review_summary.updated_dependencies.count, tags: ["change_type:updated"])


    review_summary.manifests.each do |manifest|
      GitHub.dogstats.count("dependency_graph.dependency_review.manifest_dependencies_count", manifest.dependencies.count)
    end
  end
end
