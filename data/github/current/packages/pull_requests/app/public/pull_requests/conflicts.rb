# typed: strict
# frozen_string_literal: true

module PullRequests
  module Conflicts
    module_function

    extend T::Sig

    # Maps the conflict types coming from GitRPC to entries in the
    # github.v1.entities.ConflictedPath.ConflictType enum.
    GIT_TO_HYDRO = T.let({
      submodule_conflict: "SUBMODULE",
      filename_conflict: "FILENAME",
      mode_conflict: "MODE",
      regular_conflict: "REGULAR",
      not_in_theirs: "NOT_IN_THEIRS",
      not_in_ours: "NOT_IN_OURS"
    }.freeze,
    T::Hash[Symbol, String])

    # One of three parts of a gitrpc conflict triple.
    GitRPCConflictSide = T.type_alias do
      T.nilable({
        oid: String,
        file_size: Integer,
        binary: T::Boolean
      })
    end

    # The gitrpc conflict triple.
    GitRPCConflict = T.type_alias do
      {
        base: GitRPCConflictSide,
        ours: GitRPCConflictSide,
        theirs: GitRPCConflictSide,
        type: Symbol
      }
    end

    # Translate a description of a git merge conflict coming from gitrpc into
    # the format used by the github.pull_requests.v1.MergeConflict hydro
    # schema.
    sig do
      params(
        pull: PullRequest,
        base_commit_oid: String,
        head_commit_oid: String,
        conflicts: T::Hash[Symbol, GitRPCConflict],
        more_conflicts_exist: T::Boolean,
        queued: T::Boolean
      ).returns(
        T::Hash[Symbol, T.untyped]
      )
    end
    def self.to_hydro(pull:, base_commit_oid:, head_commit_oid:, conflicts:, more_conflicts_exist:, queued:)
      {
        repository_id: pull.repository_id,
        base_commit_oid:,
        head_commit_oid:,
        conflicts: conflicts.map do |path, conflict|
          {
            path: path,
            conflict_type: PullRequests::Conflicts::GIT_TO_HYDRO.fetch(conflict[:type]),
            **map_triple(conflict)
          }
        end,
        more_conflicts_exist:,
        queued:,
        pull_request_id: pull.id,
      }
    end

    CI = T.type_alias { Hydro::Schemas::Github::V1::Entities::ConflictItem }

    TRIPLE_MAP = T.let({ ours: :base,  theirs: :head, ancestor: :ancestor }.freeze, T::Hash[Symbol, Symbol])
    KEY_MAP = T.let({ blob_oid: :oid, size: :file_size, is_binary: :binary }.freeze, T::Hash[Symbol, Symbol])

    # Translate a GitRPC conflict triple into the equivalent Hydro format.
    sig do
      params(
        conflict: GitRPCConflict
      ).returns(
        T::Hash[Symbol, { ours: CI, theirs: CI, ancestor: CI }]
      )
    end
    def map_triple(conflict)
      {}.tap do |result|
        TRIPLE_MAP.each do |hydro_side, gitrpc_side|
          result[hydro_side] = {}
          KEY_MAP.each do |hydro_key, gitrpc_key|
            result[hydro_side][hydro_key] = conflict.dig(gitrpc_side, gitrpc_key)
          end
        end
      end
    end
  end
end
