# typed: strict
# frozen_string_literal: true

module Repositories
  class DiffCreator
    sig do
      params(
        repo: Repository,
        oid: T.nilable(String),
        path: String,
        contents: T.nilable(String),
        old_path: T.nilable(String),
        diff_options: T::Hash[Symbol, Integer]
      ).void
    end
    def initialize(repo:, oid:, path:, contents: nil, old_path: nil, diff_options: {})
      @repo = T.let(repo, Repository)
      @parent_oid = T.let(oid, T.nilable(String))
      @path = T.let(path, String)
      @contents = T.let(contents, T.nilable(String))
      @old_path = T.let(old_path, T.nilable(String))
      @diff_options = T.let(diff_options, T::Hash[Symbol, Integer])
    end

    sig { returns(T.any(GitHub::Diff, FalseClass)) }
    def build_diff
      metadata = {
        message: "Temporary Commit for Preview",
        author: User.ghost,
      }

      synthetic_commit = @repo.commits.create(metadata, @parent_oid.presence, sign: false, skip_rule_evaluation: true) do |commit_files|
        if @old_path.present?
          commit_files.move(@old_path.b, @path.b, @contents&.b)
        elsif @contents
          commit_files.add(@path.b, @contents.b)
        else
          commit_files.remove(@path.b)
        end
      end

      return false unless synthetic_commit

      if max_files
        synthetic_commit.set_diff_options(max_files: max_files)
      end

      synthetic_commit.diff
    rescue Git::Ref::ComparisonMismatch, GitRPC::Failure, ArgumentError
      false
    end

    sig { returns(T.any(Integer, FalseClass)) }
    def max_files
      @diff_options[:max_files] || false
    end
  end
end
