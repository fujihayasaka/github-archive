# typed: true
# frozen_string_literal: true

module Pushes
  module ChangedFilesHelper
    extend T::Helpers

    abstract!

    include Kernel

    # String SHA of the ref before the push.
    sig { abstract.returns(T.nilable(String)) }
    def before; end

    # String SHA of the ref after the push.
    sig { abstract.returns(T.nilable(String)) }
    def after; end

    # String name of the ref: "refs/heads/master"
    sig { abstract.returns(T.nilable(String)) }
    def ref; end

    # The User who pushed
    sig { abstract.returns(T.nilable(Users::IUser)) }
    def pusher; end

    # The Repository instance for this Push.
    sig { abstract.returns(T.nilable(Repositories::IRepository)) }
    def repository; end

    sig { abstract.returns(T::Boolean) }
    def spokes_api_fail_fast_enabled; end

    # Public: Changed files, interpreted as additions, deletions, modifications, renames, etc.
    #
    # decompose_renames - Boolean, when true, treats file renaming as an addition and deletion.
    # paths - Array of strings to filter the changed files to
    #
    # See https://git-scm.com/docs/git-diff#_raw_output_format to understand
    # the splitting logic.
    #
    # Returns an Array of ChangedFiles.
    def changed_files(decompose_renames: false, paths: nil)
      tags = [
        "decompose_renames:#{decompose_renames}",
        "cached_in_memory:#{@changed_files.present?}",
        "paths:#{paths.present?}"
      ]
      GitHub.dogstats.distribution_time "push.changed_files.time", tags: tags do
        @changed_files ||= {}
        @changed_files[(paths || []) + [decompose_renames.to_s]] ||= begin
          return [] unless repository.present?
          get_changed_files(decompose_renames: decompose_renames, paths: paths)
        end
      end
    end

    def get_changed_files(decompose_renames:, paths:)
      get_changed_files_spokes_api(decompose_renames: decompose_renames, paths: paths)
    end

    def get_changed_files_spokes_api(decompose_renames:, paths:)
      if GitHub.context[:actor_id].nil? && !pusher.nil?
        GitHub.context.push(actor_id: pusher&.id)
      end

      entries = if spokes_api_fail_fast_enabled
        SpokesAPI.with_fail_fast do
          T.cast(repository, Repository).spokes_api.compare_oids( # rubocop:todo GitHub/AvoidCast
            before: before,
            after: after,
            include_renames: !decompose_renames,
            max_entries: 50_000,
            paths: paths
          )
        end
      else
        T.cast(repository, Repository).spokes_api.compare_oids( # rubocop:todo GitHub/AvoidCast
          before: before,
          after: after,
          include_renames: !decompose_renames,
          max_entries: 50_000,
          paths: paths
        )
      end

      entries.map do |diff_entry|
        change_type = case diff_entry.status
        when :STATUS_ADDITION then Repositories::ChangedFile::ADDITION
        when :STATUS_DELETION then Repositories::ChangedFile::DELETION
        when :STATUS_RENAME then Repositories::ChangedFile::RENAMING
        when :STATUS_MODIFICATION then Repositories::ChangedFile::MODIFYING
        when :STATUS_TYPE then Repositories::ChangedFile::TYPE
        end

        Repositories::ChangedFile.new(
          repository: repository,
          ref: ref,
          previous_oid: diff_entry.source_oid,
          oid: diff_entry.destination_oid,
          change_type: change_type,
          path: diff_entry.destination_path,
          previous_path: diff_entry.source_path,
          score: diff_entry.score
        )
      end
    rescue SpokesAPI::Error => e
      GitHub.dogstats.increment "push.get_changed_files_spokes_api.error", tags: ["error:#{e.class.name}"]
      raise if e.is_a?(SpokesAPI::ResourceExhausted) && spokes_api_fail_fast_enabled
      nil
    end

    def readme_change
      @readme_change ||= begin
        Array(changed_files).detect { |file| PreferredFile.valid_path?(type: :readme, path: file.path) }
      end
    end

    def readme_changed?
      readme_change.present?
    end

    def org_profile_readme_change
      @org_profile_readme_change ||=
        Array(changed_files).detect { |file| file.path == "profile/README.md" }
    end

    def org_profile_readme_changed?
      org_profile_readme_change.present?
    end

    def dependabot_config_changed?
      return @dependabot_config_changed if defined?(@dependabot_config_changed)
      return false unless ref == T.cast(repository, Repository).default_branch_ref&.qualified_name # rubocop:todo GitHub/AvoidCast
      return false unless changed_files.present?

      GitHub.dogstats.time("push.dependabot_config_changed") do
        @dependabot_config_changed = changed_files.any? do |file|
          Dependabot::CONFIG_FILE_PATH_PATTERN.match?(file.path) || Dependabot::CONFIG_FILE_PATH_PATTERN.match?(file.previous_path)
        end
      end
    end

    def funding_change_type
      return false unless changed_files
      @funding_change_type ||= changed_files.detect do |file|
        PreferredFile.valid_path?(type: :funding, path: file.path)
      end&.change_type
    end

    def funding_file_changed?
      funding_change_type.present?
    end
  end
end
