# typed: strict
# frozen_string_literal: true

module GitHubUI
  class PreviewManifestStore
    class MissingError < StandardError
    end
    REDIS_KEY_PREFIX = "preview_manifest_sha:"

    sig { params(git_sha: String).returns(T::Boolean) }
    def self.allowed?(git_sha:)
      GitHubUI::Redis.client.exists?("#{REDIS_KEY_PREFIX}#{git_sha}")
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.logger.error("Redis error when checking SHA: #{e.message}", {
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
      false
    end

    sig { params(git_sha: SHA, manifest: ManifestData).returns(ManifestData) }
    def self.set(git_sha:, manifest:)
      raise "Expected 'alloy' data in UI manifest" unless manifest.key?("alloy")

      store_manifest(git_sha: git_sha, manifest: manifest)

      manifest
    end

    sig { params(git_sha: SHA, manifest: ManifestData).void }
    def self.store_manifest(git_sha:, manifest:)
      GitHubUI::Redis.client.set("#{REDIS_KEY_PREFIX}#{git_sha}", true, ex: PREVIEW_TTL)
      GitHubUI::ManifestStore.set(target: "preview", git_sha: git_sha, manifest: manifest)
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.dogstats.increment("ui.gh.manifest.set.failure", tags: ["target:preview", "type:redis"])
      GitHub.logger.error("Error when setting manifest: #{e.message}", {
        "target": "preview",
        "git_sha": git_sha,
        "code.namespace": self.class.name,
        "code.function": __method__,
      })
    end

    sig { void }
    def self.clear
      GitHubUI::Redis.client.flushall
    end
  end
end
