# typed: true
# frozen_string_literal: true

module Repository::LatestReleaseDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  MSEARCH_BATCH_SIZE = 50

  # ES error classes whose per-repo equivalent (`Search::Query#execute`)
  # rescues and turns into an empty result set (→ `models.first` → nil).
  # We mirror that policy at the msearch level so the candidate stays
  # behavior-compatible with the per-repo `fetch_latest_release` control.
  MSEARCH_RESCUED_ES_ERRORS = [
    ElastomerClient::Client::RequestError,
    ElastomerClient::Client::ServerError,
    ElastomerClient::Client::TimeoutError,
  ].freeze

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    has_one :repository_latest_release, dependent: :destroy
    has_one :saved_latest_release, through: :repository_latest_release, source: :release

    batch_method(:latest_release) do |repos, actor|
      GitHub::PrefillAssociations.prefill_associations(repos, [:saved_latest_release])

      if FeatureFlag.vexi.enabled?(:batch_latest_release_es_lookups, actor, default: false)
        # Separate cached vs. fallback repos up front so only repos that
        # actually need an ES query go through the msearch path.
        cached_results = {}
        fallback_repos = []

        repos.each do |repo|
          cached = repo.repository_latest_release
          if cached&.valid?
            cached_results[repo] = cached.release
          else
            # Mirror fetch_latest_release's fallback telemetry so the cache
            # miss/invalid signal is preserved when a repo needs an ES query,
            # regardless of whether it then takes the per-repo or msearch path.
            GitHub.dogstats.increment(
              "latest_release.fallback",
              { tags: ["reason:#{cached.nil? ? "latest_release_nil" : "latest_release_invalid"}"] },
            )
            fallback_repos << repo
          end
        end

        fallback_results = if fallback_repos.any?
          Repository::LatestReleaseDependency.batch_fetch_releases_via_msearch(fallback_repos, actor)
        else
          {}
        end

        cached_results.merge(fallback_results)
      else
        repos.index_with do |repo|
          repo.fetch_latest_release(actor)
        end
      end
    end
  end

  # Batch-fetch the latest published, non-draft, non-prerelease release for
  # repos that need an ES fallback, using a single batched msearch HTTP call.
  # Each sub-query uses Search::Queries::ReleaseQuery as the single source of
  # truth for filter construction, sort order, and result pruning — the same
  # pipeline as the per-repo fetch_latest_release fallback.
  #
  # Error policy: mirrors Search::Query#execute. RequestError, ServerError,
  # and TimeoutError (whether raised at the outer HTTP call or returned in
  # a sub-response) are rescued and converted to nil for the affected repo(s)
  # — matching what fetch_latest_release returns when its per-repo ES query
  # hits the same conditions. Other error classes (e.g. ConnectionFailed)
  # propagate, also matching the per-repo path.
  #
  # repos - Array of Repository objects that do NOT have a valid cached latest release
  # actor - The current user (may be nil for anonymous requests)
  #
  # Returns a Hash of { Repository => Release or nil }
  def self.batch_fetch_releases_via_msearch(repos, actor)
    return {} if repos.empty?

    repo_releases = {}

    repos.each_slice(MSEARCH_BATCH_SIZE) do |batch|
      repo_releases.merge!(perform_msearch_batch(batch, actor))
    end

    # Preserve input order in the output hash.
    repos.each_with_object({}) { |repo, hash| hash[repo] = repo_releases[repo] }
  end

  # Private: Run msearch for one batch of repos. On any tracked ES error at
  # the outer HTTP level, return nil for every repo in the batch (matching
  # the per-repo path's rescue policy) and emit telemetry for visibility.
  def self.perform_msearch_batch(batch, actor)
    queries = batch.map { |repo| Search::Queries::ReleaseQuery.for_latest_release(repo, actor) }

    index = Elastomer::Indexes::Releases.new
    msearch_response = index.multi_search(type: "release") do |m|
      queries.each do |query|
        # msearch_params returns the per-sub-query metadata (e.g. routing),
        # already filtered to only ES-recognised msearch metadata keys.
        m.search(query.msearch_body, **query.msearch_params)
      end
    end

    responses = msearch_response["responses"] || []
    batch.each_with_index.with_object({}) do |(repo, idx), hash|
      hash[repo] = process_sub_response(repo, queries[idx], responses[idx])
    end
  rescue *MSEARCH_RESCUED_ES_ERRORS => boom
    GitHub.dogstats.increment(
      "latest_release.msearch.errors",
      tags: ["error_class:#{T.must(boom.class.name).demodulize}", "batch_size:#{batch.size}"],
    )
    Failbot.report(boom, app: "github-user", source: "batch_fetch_releases_via_msearch")
    batch.each_with_object({}) { |repo, hash| hash[repo] = nil }
  end
  private_class_method :perform_msearch_batch

  # Private: Turn one msearch sub-response into a Release (or nil).
  # Mirrors the relevant slice of Search::Query#execute: prune the hits,
  # extract the first model.
  #
  # On per-sub-query error or timeout, returns nil for that repo and emits
  # telemetry. This matches Search::Query#execute, which rescues server-side
  # errors and yields an empty result set for the affected query.
  def self.process_sub_response(repo, query, sub_response)
    return nil if sub_response.nil?

    if sub_response["error"] || sub_response["timed_out"]
      kind = sub_response["timed_out"] ? "timeout" : "error"
      GitHub.dogstats.increment(
        "latest_release.msearch.sub_response_error",
        tags: ["kind:#{kind}"],
      )
      return nil
    end

    hits = sub_response.dig("hits", "hits") || []
    return nil if hits.empty?

    pruned = query.prune_msearch_hits(hits)
    pruned.first&.dig("_model")
  end
  private_class_method :process_sub_response

  def set_latest_release(release)
    return unless release.present?
    # Call .destroy on this model after creating it to avoid auto saving a duplicate when #save is called on the release.
    # We are running model validation manually in this way because .upsert does not do any validation.
    return unless RepositoryLatestRelease.new(repository: self, release: release).destroy.valid?

    RepositoryLatestRelease.upsert({ repository_id: self.id, release_id: release.id })
  end

  def fetch_latest_release(user)
    if repository_latest_release && repository_latest_release&.valid?
      T.must(repository_latest_release).release
    else
      # Fallback to querying elasticsearch if we don't have a valid latest release stored
      GitHub.dogstats.increment(
        "latest_release.fallback",
        { tags: ["reason:#{repository_latest_release.nil? ? "latest_release_nil" : "latest_release_invalid"}"] }
        )
      Search::Queries::ReleaseQuery.for_latest_release(T.cast(self, ::Repository), user).execute.models.first
    end
  end
end
