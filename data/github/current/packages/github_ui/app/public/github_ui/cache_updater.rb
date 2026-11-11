# typed: strict
# frozen_string_literal: true

module GitHubUI
  # CacheUpdater is responsible for updating the UI manifest cache
  # by fetching the manifest asynchronously.
  #
  # It is initialized with a target and a git SHA, and it starts the
  # asynchronous fetch when the `start` method is called.
  #
  # The `sync` method waits for the fetch to complete and updates the
  # manifest cache if the fetch was successful.
  class CacheUpdater

    sig { returns(T.nilable(ConcurrentFaraday::FutureResponse[T.untyped])) }
    attr_reader :promise

    sig { params(target: String, sha: String).void }
    def initialize(target:, sha:)
      @target = T.let(target, String)
      @sha = T.let(sha, String)
      @promise = T.let(nil, T.nilable(ConcurrentFaraday::FutureResponse[T.untyped]))
    end

    sig { void }
    def start
      if GitHub.after_response.enabled?
        if GitHubUI::ManifestStore.manifest_from_ui_deploys?
          begin
            @promise = GitHubUI::ManifestStore.get_manifest_from_ui_deploys_async(git_sha: @sha, target: @target)
          rescue StandardError => e
            GitHub.logger.error("Failed to start UI deploys async request, falling back to CDN", {
              "exception.message": e.message,
              "git_sha": @sha,
              "target": @target,
              "code.namespace": self.class.name,
              "code.function": __method__,
            })
            @promise = nil
          end

          # Fall back to CDN if UI deploys async fails or returns nil
          @promise = GitHubUI::ManifestStore.get_manifest_from_cdn_async(git_sha: @sha) unless @promise.present?
        else
          @promise = GitHubUI::ManifestStore.get_manifest_from_cdn_async(git_sha: @sha)
        end

        return unless @promise.present?

        GitHub.after_response.perform(:update_ui_manifest_cache) do
          sync
        end
      end
    end

    sig { void }
    def sync
      return unless @promise.present?

      start_time = Time.now
      response = @promise.sync

      manifest = if response.success?
        JSON.parse(response.body).with_indifferent_access
      else
        nil
      end

      if manifest.present?
        Cache.set_manifest(sha: @sha, manifest: manifest.with_indifferent_access, target: @target)
        GitHubUI::ManifestStore.store_manifest_in_disk(git_sha: @sha, manifest: manifest.with_indifferent_access)
      end

      if response.present?
        # ms to seconds
        request_time = (@promise.instrument_event.duration / 1000).round(2)
        store_type = GitHubUI::ManifestStore.manifest_from_ui_deploys? ? "ui_deploys_async" : "cdn_async"
        GitHub.dogstats.distribution("ui.gh.manifest.get_manifest.time", request_time, tags: ["target:#{@target}", "type:#{store_type}"])
        GitHub.dogstats.increment("ui.gh.manifest.get_manifest.success", tags: ["target:#{@target}", "type:#{store_type}"])
      else
        store_type = GitHubUI::ManifestStore.manifest_from_ui_deploys? ? "ui_deploys_async" : "cdn_async"
        GitHub.dogstats.increment("ui.gh.manifest.get_manifest.failure", tags: ["target:#{@target}", "type:#{store_type}"])
      end
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.logger.error("Failed to update manifest cache", {
        "exception.message": e.message,
        "git_sha": @sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    ensure
      if start_time.present?
        blocking_time = Time.now - start_time
        GitHub.dogstats.distribution("ui.gh.manifest.cache_updater.blocking_time", blocking_time, tags: ["target:#{@target}"])
      end
    end
  end
end
