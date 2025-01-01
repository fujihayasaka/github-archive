# typed: true
# frozen_string_literal: true

module DependencyReviewHelper
  include DependencyReview::VulnerabilityHelper
  include Kernel

  DEFAULT_MANIFESTS_PER_PAGE = 1000

  ECOSYSTEM_MAPPINGS = {
    PACKAGE_MANAGER_UNKNOWN: "unknown",
    PACKAGE_MANAGER_RUBYGEMS: "rubygems",
    PACKAGE_MANAGER_NPM: "npm",
    PACKAGE_MANAGER_PIP: "pip",
    PACKAGE_MANAGER_MAVEN: "maven",
    PACKAGE_MANAGER_NUGET: "nuget",
    PACKAGE_MANAGER_COMPOSER: "composer",
    PACKAGE_MANAGER_GOMOD: "gomod",
    PACKAGE_MANAGER_RUST: "cargo",
    PACKAGE_MANAGER_ACTIONS: "actions",
    PACKAGE_MANAGER_PUB: "PUB",
    PACKAGE_MANAGER_SWIFT: "swift",
  }

  # currently unused
  def get_pull_diff(repo:, pull:, decompose_updates: false, page: nil, per_page: nil)
    load_vulns = pull.state == :open

    generate_diff(repo, base_sha: pull.merge_base, target_sha: pull.head_sha, load_vulnerabilities: load_vulns, decompose_updates: decompose_updates, page: page, per_page: per_page)
  end

  # Typically we only want to share vulns on SHAs in a pull request that is open
  def get_shas_diff(repo:, base_sha:, target_sha:, load_vulns: false, decompose_updates: false, include_dependency_snapshots: false, page: nil, per_page: nil)
    generate_diff(
      repo, base_sha: base_sha, target_sha: target_sha,
      load_vulnerabilities: load_vulns, decompose_updates: decompose_updates,
      include_dependency_snapshots: include_dependency_snapshots,
      page: page, per_page: per_page)
  end

  # given a "legacy DR" (rich diff) style snapshot diff,
  # reshape to conform to the new DR API response format
  def reshape_for_api_response(diff)
    start_time = GitHub::Dogstats.monotonic_time
    return [] if diff.nil?

    diff.manifests.map do |manifest|
      manifest.dependencies.map do |dep|
        {
          change_type: dep.change_type,
          manifest: manifest.path,
          ecosystem: ECOSYSTEM_MAPPINGS[manifest.type] || manifest.type.to_s.downcase,
          name: dep.package_name,
          version: dep.version,
          package_url: dep.purl,
          license: is_license?(dep.license) ? dep.license : nil,
          source_repository_url: dep.repo_url,
          scope: dep.scope,
          vulnerabilities: reshape_vulnerabilities_for_api(dep.vulnerabilities),
        }
      end
    end.flatten
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("dependency_graph.dependency_review.helper.reshape_diff", elapsed)
  end

  def get_changed_manifests(repo, base_sha:, target_sha:)
    start_time = GitHub::Dogstats.monotonic_time
    diff = GitHub::Diff.new(repo, base_sha, target_sha)
    changed_manifests = diff.summary.deltas.select { |d| DependencyManifestFile.recognized_path?(path: d.new_file.path) }

    manifest_changes(changed_manifests)
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("dependency_graph.dependency_review.helper.get_changed_manifests", elapsed)
  end

  private

  def generate_diff(repo, base_sha:, target_sha:, load_vulnerabilities: false, decompose_updates: false, include_dependency_snapshots: false, page: nil, per_page: nil)
    return unless repo.dependency_review_enabled?

    changed_manifests = get_changed_manifests(repo, base_sha: base_sha, target_sha: target_sha)
    return nil if changed_manifests.blank? && !include_dependency_snapshots

    review_summary = get_review_summary(
      repo, base_sha: base_sha, target_sha: target_sha,
      limit_to_files: changed_manifests, decompose_updates: decompose_updates,
      include_dependency_snapshots: include_dependency_snapshots,
      page: page, per_page: per_page)

    # TODO - I'm not sure I like these in-place changes but I don't want to modify existing rich diff logic
    # so I'll come back to this in the final consolidation
    review_summary&.load_vulnerabilities(vulnerability_loader: self, decompose_updates: decompose_updates) if load_vulnerabilities
    review_summary&.sort_dependencies

    review_summary
  end

  def reshape_vulnerabilities_for_api(vulnerabilities)
    vulnerabilities.map do |vulnerability|
      {
        severity: vulnerability.severity,
        advisory_ghsa_id: vulnerability.advisory_ghsa_id,
        advisory_summary: vulnerability.advisory_summary,
        advisory_url: URI.join(GitHub.url, "/advisories/", vulnerability.advisory_ghsa_id).to_s,
      }
    end
  end

  # resolve pagination params if present and apply API-specific defaults.
  # for use with new DR API only! Not back compatible with legacy DR
  def resolve_api_pagination_params(params)
    page, per_page = nil, nil
    paginating = params[:page] || params[:per_page]

    if paginating
      page = [1, params[:page].to_i].max
      per_page = params[:per_page].nil? ? DEFAULT_MANIFESTS_PER_PAGE : params[:per_page].to_i
    end

    [page, per_page]
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
    GitHub.dogstats.count("dependency_graph.dependency_review.helper.manifest_changes", base.count, tags: ["diff_range:merge_base"])
    GitHub.dogstats.count("dependency_graph.dependency_review.helper.manifest_changes", target.count, tags: ["diff_range:head"])
    { base: base, target: target }
  end

  # for legacy DR compatibility, set:
  # - decompose_updates: false
  # - page: nil
  # - per_page: nil
  def get_review_summary(repo, base_sha:, target_sha:, limit_to_files:, decompose_updates:, include_dependency_snapshots:, page:, per_page:)
    start_time = GitHub::Dogstats.monotonic_time
    begin
      client = DependencyReview::SnapshotClient.new
      cache_key = dependency_review_cache_key(repo, base_sha, target_sha, page, per_page)
      snapshot_diff = T.let(nil, T.untyped)
      tag_value = decompose_updates ? "api" : "legacy"

      snapshot_diff_encoded = GitHub.cache.fetch(cache_key, force: (Rails.env.development? || include_dependency_snapshots)) do
        snapshot_diff = client.get_snapshots_diff(
          repository_id: repo.id,
          base_sha: base_sha,
          target_sha: target_sha,
          repository_nwo: repo.nwo,
          repository_public: repo.public,
          repository_owner_id: repo.owner_id,
          limit_to_files: limit_to_files,
          decompose_updates: decompose_updates,
          include_dependency_snapshots: include_dependency_snapshots,
          page: page,
          per_page: per_page)
        GitHub.dogstats.increment("dependency_graph.dependency_review.helper.snapshot_cache.miss", tags: ["source:#{tag_value}"])
        DependencyGraphAPI::V1::GetSnapshotsDiffResponse.encode(snapshot_diff)
      end
      GitHub.dogstats.increment("dependency_graph.dependency_review.helper.snapshot_cache.total", tags: ["source:#{tag_value}"])

      if snapshot_diff.nil? && snapshot_diff_encoded
        snapshot_diff = DependencyGraphAPI::V1::GetSnapshotsDiffResponse.decode(snapshot_diff_encoded)
      end

      snapshot_diff = apply_mock_data(snapshot_diff) if Rails.env.development?

      review_summary = DependencyReview::ReviewSummary.from_twirp(snapshot_diff)

      # TODO: revisit this once get_review_summary is integrated w/legacy DR flow:
      # condition API or rich_diff sourced calls w/"source" tag, using
      # decompose_updates or similar sentinel value; then remove old DR metrics as dups
      version_tag = "source:api"
      GitHub.dogstats.count("dependency_graph.dependency_review.helper.manifests_count",
        review_summary.manifests.count,
        tags: [version_tag])

      # Report the requested page size so we can see if the requestor is using pagination
      # (we expect them to probably not be)
      GitHub.dogstats.count("dependency_graph.dependency_review.helper.manifests_requested_page_size",
        per_page.nil? ? 0 : per_page,
        tags: [version_tag])

      GitHub.dogstats.count("dependency_graph.dependency_review.helper.dependencies_count",
        review_summary.added_dependencies.count,
        tags: ["change_type:added", version_tag])
      GitHub.dogstats.count("dependency_graph.dependency_review.helper.dependencies_count",
        review_summary.removed_dependencies.count,
        tags: ["change_type:removed", version_tag])
      # only expect to see these in "legacy DR" responses (not meant for the public API)
      GitHub.dogstats.count("dependency_graph.dependency_review.helper.dependencies_count",
        review_summary.updated_dependencies.count,
        tags: ["change_type:updated", version_tag])

      review_summary
    # TODO: review these when integrating legacy DR controller to share new helper
    rescue Faraday::TimeoutError => error
      GitHub.dogstats.increment("dependency_graph.dependency_review.helper.get_review_summary.error", tags: ["error_type:timeout"])
      Failbot.report(error, app: "github-dependency-graph")
    rescue DependencyGraph::BaseTwirpClient::NotFoundError => error
      GitHub.dogstats.increment("dependency_graph.dependency_review.helper.get_review_summary.error", tags: ["error_type:not_found"])
    rescue DependencyGraph::BaseTwirpClient::CircuitBrokenError => error
      GitHub.dogstats.increment("dependency_graph.dependency_review.helper.get_review_summary.error", tags: ["error_type:circuit_broken"])
      Failbot.report(error, app: "github-dependency-graph")
    rescue DependencyGraph::BaseTwirpClient::Error => error
      GitHub.dogstats.increment("dependency_graph.dependency_review.helper.get_review_summary.error", tags: ["error_type:error"])
      Failbot.report(error, app: "github-dependency-graph")
    ensure
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("dependency_graph.dependency_review.helper.get_review_summary", elapsed)
    end
  end

  # Given a Repository model, attempt to resolve all
  # commit SHAs relevant to snapshot diff generation:
  def resolve_diff_range(repo, base, head)
    head_sha = nil
    base_sha = nil
    merge_base_sha = nil

    # "best effort" is fine for this use case
    begin
      comparison = repo.comparison(base, head)
      head_sha = comparison.head_sha
      base_sha = comparison.base_sha
      merge_base_sha = comparison.merge_base

    # this is because GitRPC can throw a wide variety of errors
    # and we don't care, we just fall back to base_sha. details:
    # https://github.com/github/dependency-graph/issues/960
    rescue StandardError => e # rubocop:todo Lint/RescueException
      err_type = e.class.to_s.downcase
      GitHub.dogstats.increment("dependency_graph.dependency_review.helper.diff_range.resolve.error", tags: ["error:#{err_type}"])
      GitHub.logger.error({
        "gh.repo.id" => repo.id,
        "gh.pull_request.head_sha" => head_sha,
        "gh.pull_request.base_sha" => base_sha,
        "gh.pull_request.merge_base_sha" => merge_base_sha,
        "gh.comparison.base_rev" => base,
        "gh.comparison.head_rev" => head,
        :exception => e
      })
    end

    # if a valid merge base was found, it is the proper
    # base for the snapshot diff commit range
    base_sha = merge_base_sha if merge_base_sha.present?

    [base_sha, head_sha]
  end

  # the DR API composes a cache key after the diff range is resolved
  # to commit SHAs. base_sha may be original or resolved merge base
  def dependency_review_cache_key(repo, base_sha, target_sha, page = nil, per_page = nil)
    now = Time.now.utc
    page = page ? "page_#{page}" : nil
    per_page = per_page ? "per_page_#{per_page}" : nil
    timestamp = [now.year, now.month, now.day, now.hour].join(":")

    ["dependency_review_api",
      repo.id,
      base_sha,
      target_sha,
      page,
      per_page,
      timestamp,
    ].compact.join(":")
  end

  def is_license?(license)
    result = !license.blank? && license != "NOASSERTION"
    GitHub.dogstats.increment("dependency_graph.dependency_review.helper.license_coverage", tags: ["found:#{result}"])

    result
  end

  def apply_mock_data(snapshot_diff)
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

    manifest_to_add_to = snapshot_diff.changed_manifests.find { |m| m.type == :PACKAGE_MANAGER_RUBYGEMS }
    manifest_to_add_to.dependencies.push(dependency_diff_add_octokit) unless manifest_to_add_to.blank?

    snapshot_diff
  end
end
