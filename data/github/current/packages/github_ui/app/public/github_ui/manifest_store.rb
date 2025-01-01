# typed: strict
# frozen_string_literal: true

module GitHubUI
  class ManifestStore
    class MissingError < StandardError
    end

    ManifestData = T.type_alias { T::Hash[String, T.untyped] }
    SHA = T.type_alias { String }
    Target = T.type_alias { String }

    @manifest_store = T.let({}, T::Hash[SHA, ManifestData])

    sig { params(target: String).returns(ManifestData) }
    def self.get(target:)
      git_sha = self.get_sha(target: target)
      self.get_manifest(git_sha: git_sha)
    end

    sig { params(target: String).returns(SHA) }
    def self.get_sha(target:)
      # TODO: Use Redis to get the SHA
      git_sha = UIManifest.find_by(target: target)&.sha

      raise MissingError.new("Missing SHA for target: #{target}") if !git_sha.present?

      git_sha
    end

    sig { params(git_sha: String).returns(ManifestData) }
    def self.get_manifest(git_sha:)
      manifest = @manifest_store[git_sha]
      # TODO: Use Redis as first fallback
      # Only read from DB if it's not in Cache or Redis
      if manifest.blank?
        manifest = UIManifest.find_by(sha: git_sha)&.manifest
        @manifest_store[git_sha] = manifest
      end

      raise MissingError.new("Missing manifest for SHA: #{git_sha}") if !manifest.present?

      manifest
    end

    sig { params(target: Target, git_sha: SHA, manifest: ManifestData).returns(ManifestData) }
    def self.set(target:, git_sha:, manifest:)
      UIManifest.upsert({ target: target, sha: git_sha, manifest: manifest })
      @manifest_store[git_sha] = manifest

      manifest
    end

    sig { void }
    def self.clear
      @manifest_store = {}
    end
  end
end
