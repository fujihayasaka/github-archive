# typed: strict
# frozen_string_literal: true

module Marketplace
  class Domain
    class RepositorySettings < GH::Domain::Base

      # File names and extensions that indicate the presence of a mobile app.
      MOBILE_NAMES = T.let(%w(AndroidManifest.xml android ios).freeze, T::Array[String])
      MOBILE_EXTENSIONS = T.let(%w(.csproj .fsproj .sln .xcodeproj .xcworkspace).freeze, T::Array[String])
      MOBILE_KEY_PREFIX = "mobile-repo:"
      DOCKER_FILE_KEY_PREFIX = "docker-file-repo:"

      # Public: key for storing if it's a mobile repo
      sig { params(repo_id: Integer).returns(String) }
      def mobile_key(repo_id)
        MOBILE_KEY_PREFIX + repo_id.to_s
      end

      # Public: key for storing if it's a docker repo
      sig { params(repo_id: Integer).returns(String) }
      def docker_file_key(repo_id)
        DOCKER_FILE_KEY_PREFIX + repo_id.to_s
      end

      # Public: Is mobile repo?
      sig { params(repo_id: Integer).returns(T::Boolean) }
      def is_mobile?(repo_id)
        value = GitHub.kv.get(mobile_key(repo_id)).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        value == "1"
      end

      # Public: Is docker repo?
      sig { params(repo_id: Integer).returns(T::Boolean) }
      def has_docker_file?(repo_id)
        value = GitHub.kv.get(docker_file_key(repo_id)).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        value == "1"
      end

      # Public: Clear repo from being marked a mobile repo
      sig { params(repo_id: Integer).void }
      def clear_mobile_status(repo_id)
        if GitHub.kv.exists(mobile_key(repo_id)).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
          GitHub.kv.del(mobile_key(repo_id)) # rubocop:todo GitHub/DoNotUseGlobalKv
          GitHub.dogstats.increment("repository.mobile.clear")
        else
          GitHub.dogstats.increment("repository.mobile.untracked")
        end
      end

      # Public: Clear repo from being marked a docker repo
      sig { params(repo_id: Integer).void }
      def clear_docker_file_status(repo_id)
        if GitHub.kv.exists(docker_file_key(repo_id)).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
          GitHub.kv.del(docker_file_key(repo_id)) # rubocop:todo GitHub/DoNotUseGlobalKv
          GitHub.dogstats.increment("repository.docker_file.clear")
        else
          GitHub.dogstats.increment("repository.docker_file.untracked")
        end
      end

      # This mobile scan is meant to be lightweight, and will likely generate
      # false positives. In the context of showing mobile vs non-mobile CTA
      # links that's OK, but long term we should investigate more comprehensive
      # options.
      # Public: Mark a repo if it's mobile
      sig { params(repo: ::Repositories::IRepository).returns(String) }
      def set_mobile_status(repo) # rubocop:todo Metrics/MethodLength
        head = T.cast(repo, Repository).ref_to_sha(repo.default_branch) # rubocop:todo GitHub/AvoidCast
        return "0" if head.nil?

        entries = T.cast(repo, Repository).tree_entries(head, nil, recursive: true)[1] # rubocop:todo GitHub/AvoidCast
        mobile_token = entries.detect do |ent|
          ent.name.in?(MOBILE_NAMES) ||
          File.extname(ent.name).in?(MOBILE_EXTENSIONS)
        end

        cached_status = GitHub.kv.get(mobile_key(T.must(repo.id))).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        current_status = mobile_token.nil? ? "0" : "1"

        if current_status != cached_status
          GitHub.kv.set(mobile_key(T.must(repo.id)), current_status) # rubocop:todo GitHub/DoNotUseGlobalKv
          event = cached_status.nil? ? "set" : "change"
          GitHub.dogstats.increment("repository.mobile.#{event}", tags: ["status:#{current_status}"])
        else
          GitHub.dogstats.increment("repository.mobile.unchanged")
        end

        current_status
      end

      # Public: Mark a repo if it's docker
      sig { params(repo: ::Repositories::IRepository).returns(String) }
      def set_docker_file_status(repo) # rubocop:todo Metrics/MethodLength
        head = T.cast(repo, Repository).ref_to_sha(repo.default_branch) # rubocop:todo GitHub/AvoidCast
        return "0" if head.nil?

        entries = T.cast(repo, Repository).tree_entries(head, nil, recursive: false)[1] # rubocop:todo GitHub/AvoidCast
        docker_files = entries.detect do |ent|
          ent.name == "Dockerfile"
        end

        cached_status = GitHub.kv.get(docker_file_key(T.must(repo.id))).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        current_status = docker_files.nil? ? "0" : "1"

        if current_status != cached_status
          GitHub.kv.set(docker_file_key(T.must(repo.id)), current_status) # rubocop:todo GitHub/DoNotUseGlobalKv
          event = cached_status.nil? ? "set" : "change"
          GitHub.dogstats.increment("repository.dockerfile.#{event}", tags: ["status:#{current_status}"])
        else
          GitHub.dogstats.increment("repository.dockerfile.unchanged")
        end

        current_status
      end

      # Public: Returns true if the repository has CI services (including the
      # GitHub Actions app) operating.
      sig { params(repository: ::Repositories::IRepository).returns(T::Boolean) }
      def has_ci?(repository)
        # exclude first party (GitHub-owned/operated) GitHub Apps that have access
        # to write `checks` to prevent core product features from being counted as
        # CI apps. We consider GitHub Actions to count as CI so it is excluded from
        # this check.
        IntegrationInstallation.for_actions(repository).any? ||
          has_third_party_ci?(repository)
      end

      # Public: Returns true if the repository has third-party CI services operating.
      sig { params(repository: ::Repositories::IRepository).returns(T::Boolean) }
      def has_third_party_ci?(repository)
        Statuses::Service.statuses_for_repo_exist?(repository_id: repository.id) ||
          IntegrationInstallations::Public.user_installable_ci_integration_installations?(repository)
      end
    end
  end
end
