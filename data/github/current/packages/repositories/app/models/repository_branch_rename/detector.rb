# typed: true
# frozen_string_literal: true

# Given a repo and requested path including a branch, decides whether
# the path includes a since-renamed branch that the client should be
# redirected to.
module RepositoryBranchRename::Detector
  extend GitHub::UTF8

  # Result indicating to callers that their request is for a branch
  # that was renamed and they should redirect to the equivalent path
  # with an updated branch.
  class BranchWasRenamedResult
    include GitHub::UTF8

    attr_reader :redirect_branch, :path, :rename, :missing_branch_was_master

    def initialize(redirect_branch:, path:, rename:, missing_branch_was_master:)
      @redirect_branch = redirect_branch
      @path = path
      @rename = rename
      @missing_branch_was_master = missing_branch_was_master
    end

    def includes_renamed_branch?
      true
    end

    def redirect_notice
      if rename
        "Branch #{utf8(rename.old_name)} was renamed to #{rename.new_name}."
      else
        "Branch not found, redirected to default branch."
      end
    end
  end

  # Result indicating to callers that no branch rename was detected.
  NegativeResult = Class.new do
    def self.includes_renamed_branch?
      false
    end
  end

  BadArguments = Class.new(NegativeResult)
  NoRenameApplies = Class.new(NegativeResult)

  EMPTY_HASH = {}.freeze

  # Public: determine if the branch at the given path has been renamed to a different one
  #
  # repository - a Repository record
  # full_path - string containing the given path to check for renamed branches
  # all_possible_names - Boolean to indicate whether to try to find branch names from URL paths.
  # If false, specifying "a/b/c" as your full_path will only search for a branch named "a/b/c", not
  # "a", "a/b" and "a/b/c".
  #
  # Returns either an instance of BranchWasRenamedResult or NegativeResult.
  def self.call(repository:, full_path:, all_possible_names: true)
    return BadArguments unless repository && full_path

    full_path_encoded = utf8(full_path)

    parts = full_path_encoded.split("/")

    # given "a/b/c/d" our branch might be ["a", "a/b", "a/b/c", "a/b/c/d"]
    possible_branch_names = if all_possible_names
      (1..parts.size).map { |pivot| parts.first(pivot).join("/") }
    else
      [full_path_encoded]
    end

    branch_renames = repository.branch_renames
      .latest
      .finished
      .where(old_name: possible_branch_names)
      .to_a
      .uniq(&:old_name)
      .index_by(&:old_name)
      .transform_keys { |old_name| utf8(old_name) }

    branch_candidates = branch_renames.keys
    default_branch = repository.default_branch

    if default_branch != "master"
      branch_candidates << "master" # we support redirects from master
      # even if there is no record.
      branch_candidates.uniq!
    end
    # Branch names with the most '/'s take precendence. This matches the behavior
    # when disambiguating existing refs.
    branch_candidates = branch_candidates.sort_by { |candidate| -candidate.count("/") }

    missing_branch = branch_candidates.find do |candidate|
      if candidate == "master"
        # When `master` is a branch candidate, we may not have the actual rename record
        # see https://github.com/github/repos/issues/4066#issuecomment-1409999575
        # but we still support the redirect
        # Use this regex to avoid branches that aren't exactly "master"
        # (e.g. We shouldn't match "masters", "mastering", "master-branch", etc.
        # but should match "master", "master/", etc/)
        if all_possible_names
          full_path_encoded.match?(/\Amaster(\/.*)?\z/)
        else
          full_path_encoded == "master" || full_path_encoded == "master/"
        end
      else
        full_path_encoded.starts_with?(candidate)
      end
    end

    rename = branch_renames[missing_branch]
    missing_branch_was_master = missing_branch == "master"

    redirect_branch = if rename
      rename.new_name
    elsif missing_branch_was_master
      default_branch
    end

    return NoRenameApplies unless redirect_branch

    # Extract the path component (excluding the branch) from full_path
    # now that we know which is which.  For some actions, path may not
    # be specified.
    path = full_path_encoded.sub(%r{\A#{Regexp.quote(missing_branch)}/?}, "")

    # We found a rename that applies to this request!
    BranchWasRenamedResult.new(
      redirect_branch: redirect_branch,
      path: path,
      rename: rename,
      missing_branch_was_master: missing_branch_was_master
    )
  end
end
