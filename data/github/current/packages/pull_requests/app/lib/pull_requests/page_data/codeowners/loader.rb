# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Codeowners
  class Loader
    include UrlHelper

    class PathOwnership < T::Struct
      const :is_owned_by_viewer, T::Boolean
      const :owners, T::Array[String]
      # Rule line number and url are only nil when path is unowned
      const :rule_line_number, T.nilable(Integer)
      const :rule_url, T.nilable(String) # permalink to line in CODEOWNERS file
    end

    class Data < T::Struct
      const :ownership_by_path, T::Hash[String, PathOwnership]
      const :is_enabled, T::Boolean

      sig { params(path: String).returns(T::Boolean) }
      def is_owned_by_viewer?(path)
        path_info = ownership_by_path[path]
        return false unless path_info

        path_info.is_owned_by_viewer
      end
    end

    sig do
      params(
        viewer: T.nilable(User),
        paths: T::Array[String],
        refname: String, # Ref short name or oid
        repository: Repository,
      ).returns(Data)
    end
    def self.load(viewer:, paths:, refname:, repository:)
      new(viewer:, paths:, refname:, repository:).load
    end

    sig do
      params(
        viewer: T.nilable(User),
        paths: T::Array[String],
        refname: String, # Ref short name or oid
        repository: Repository,
      ).void
    end
    def initialize(viewer:, paths:, refname:, repository:)
      @viewer = viewer
      @paths = paths
      @refname = refname
      @repository = repository
    end

    sig { returns(Data) }
    def load
      ownership_by_path = {}
      codeowners = Repository::Codeowners.new(@repository, ref: @refname, paths: @paths)

      # Skip lookups if repo doesn't have a codeowners file at given ref
      unless codeowners.exists?
        return Data.new(
          ownership_by_path:,
          is_enabled: false,
        )
      end

      # Handled owned filepaths (aka paths that match a rule in CODEOWNERS file)
      codeowners.rules_by_path.each do |owned_path, rule|
        ownership_by_path[owned_path] = PathOwnership.new(
          is_owned_by_viewer: codeowners.paths_for_owner(@viewer).include?(owned_path),
          owners: rule.owners.map(&:identifier),
          rule_line_number: rule.line,
          rule_url: blob_view_path(codeowners.path, @refname, @repository, anchor: "L#{rule.line}")
        )
      end

      # Handle unowned filepaths (aka paths that don't match a rule in CODEOWNERS file)
      unowned_paths = @paths - ownership_by_path.keys
      unowned_paths.map do |unowned_path|
        ownership_by_path[unowned_path] = PathOwnership.new(
          is_owned_by_viewer: false,
          owners: [],
          rule_line_number: nil,
          rule_url: nil,
        )
      end

      Data.new(
        ownership_by_path:,
        is_enabled: true,
      )
    end
  end
end
