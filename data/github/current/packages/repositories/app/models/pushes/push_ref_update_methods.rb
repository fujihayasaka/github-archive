# typed: true
# frozen_string_literal: true

# For temporarily sharing code between the Push and RefUpdate models during the transition period when their
# functionlity overlaps.
module Pushes
  module PushRefUpdateMethods
    extend T::Helpers

    abstract!

    include Pushes::CommitsHelper
    include Pushes::ChangedFilesHelper

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(Push) }
    def push; end

    sig { abstract.returns(T.nilable(Integer)) }
    def repository_id; end

    sig { abstract.returns(Symbol) }
    def event_prefix; end

    # Getting the url for a push
    #
    # include_host - Turn off the `GitHub.url` host in the url. (default true)
    #                push.permalink(include_host: false) => `/github/github/compare/sd0979...9sd8fh`
    #
    def permalink(include_host: true)
      left = T.must(before)[0, 10]
      right = T.must(after)[0, 10]
      "#{repository&.permalink(include_host: include_host)}/compare/#{left}...#{right}"
    end
    alias_method :url, :permalink

    def notifications_author
      pusher
    end

    def event_payload
      {
        event_prefix => self,
        :repo   => repository,
        :pusher => pusher,
        :ref    => ref,
        :before => before,
        :after  => after,
      }
    end

    def on_default_branch?
      return unless ref_is_branch?
      branch_name == T.cast(repository, T.nilable(Repository))&.default_branch # rubocop:todo GitHub/AvoidCast
    end

    def dependency_manifest_changed?
      return false unless T.cast(repository, T.nilable(Repository))&.dependency_graph_enabled? # rubocop:todo GitHub/AvoidCast
      return false unless changed_files
      return @dependency_manifest_changed if defined?(@dependency_manifest_changed)
      GitHub.dogstats.time("push.dependency_manifest_changed_check") do
        @dependency_manifest_changed = changed_files&.any? do |file|
          DependencyManifestFile.recognized_path?(path: file.path)
        end
      end
    end

    def license_changed?
      RepositoryLicense.push_changed_license?(push)
    end

    def enqueue_dependency_manifest_changed_event
      return unless on_default_branch?
      return unless initial_commit? || dependency_manifest_changed?

      RepositoryDependencyManifestChangedJob.perform_later(id, repository_id)
    end

    def instrument_dependency_graph_snapshot_request
      if dependency_manifest_changed? && !GitHub.enterprise?
        manifest_files = changed_files(decompose_renames: true)&.reduce([]) do |manifest_files, file|
          next manifest_files unless DependencyManifestFile.recognized_path?(path: file.path)
          next manifest_files if file.deletion?

          manifest_files << {
            filename: File.basename(file.path),
            path: File.dirname(file.path).sub(/\A\.\z/, ""),
            blob_oid: file.oid
          }
        end

        return unless manifest_files.present?

        GlobalInstrumenter.instrument("dependency_graph.request_snapshot", {
          push_id: push.id,
          before_sha: before,
          sha: after,
          ref: ref,
          pushed_at: push.created_at,
          owner_name: repository&.owner_display_login,
          repository: repository,
          manifest_files: manifest_files,
        })
      end
    end

    def enqueue_set_license
      RepositorySetLicenseJob.perform_later(repository)
    end

    def create_check_suites
      return if CheckSuites::Public.skip_checks_for_push?(push: T.must(Repositories::Push.from_record(push)))
      CreateCheckSuitesJob.enqueue(push_id: push.id, repository_id: repository_id)
    end

    def branch_protection_rule
      return unless ref_is_branch?

      ProtectedBranch.for_repository_with_branch_name(repository, branch_name)
    end

    sig { returns T::Boolean }
    def initial_commit?
      created? && !deleted?
    end

    sig { returns(GH::Domain::Base) }
    def domain
      Repositories.domain.pushes
    end
  end
end
