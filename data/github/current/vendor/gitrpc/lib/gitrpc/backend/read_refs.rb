# typed: true
# frozen_string_literal: true

require "scientist"
require "securerandom"

module GitRPC
  class Backend
    include GitRPC::Util
    include Scientist


    # Pattern used to filter refs to only local branches, tags, and notes.
    REFS_FILTER = %r{^refs/(?:heads|guest|tags|notes)/}
    HIDDEN_REFS_FILTER = %r{^refs/__gh__($|/)}

    REFS_FILTER_ARGS = ["refs/heads", "refs/tags", "refs/guest", "refs/notes"].freeze
    HIDDEN_REFS_FILTER_ARGS = ["--exclude=refs/__gh__"].freeze

    # Public: Retrieve refs mappings for repository.
    #
    # filter - String specifying which set of refs should be returned. "default"
    #          means that only heads and tags will be returned. "extended" returns
    #          refs that would show up in `git ls-remote`. "all" returns all of the
    #          refs on the fileserver, including some that are only intended to be
    #          used inside of this app.
    #
    # Returns a Hash of { ref => oid } mappings.
    rpc_reader :read_refs
    def read_refs(filter = "default")
      ensure_valid_read_refs_filter(filter)
      filter_args = {
        "default"  => REFS_FILTER_ARGS,
        "extended" => HIDDEN_REFS_FILTER_ARGS,
        "all"      => [],
      }.fetch(filter)

      res = checked_spawn_git!("for-each-ref", ["--format=%(refname) %(objectname)"] + filter_args)
      res["out"].split("\n").to_h { |l| l.split(" ", 2) }
    end

    # Public: Retrieve target OIDs for a given set of fully qualified ref names
    # (using git instead of rugged)
    #
    # qualified_names - Array of Strings
    #
    # Returns Array of Strings as target OIDs in the same order `qualified_names` was
    # passed, with `nil` for any missing ones.
    rpc_reader :read_qualified_refs
    def read_qualified_refs(qualified_names)
      qualified_names = qualified_names.map(&:dup)
      prepare_qualified_refnames_for_git!(qualified_names)

      res = checked_spawn_git!(
        "show-ref", ["--verify", "--allow-missing", "--no-check-object-exists", "--stdin", "--end-of-options"],
        qualified_names.join("\n"))

      # Build a hash and then pull our requested refnames from it to ensure the
      # correct order and guard against the (unlikely) scenario where git
      # returns refs we didn't ask for.
      res["out"].split("\n")
        .to_h { |l| l.split(" ", 2).reverse! }
        .values_at(*qualified_names)
    end

    # Public: How many branches and tags does this repository have?
    #
    # Returns Hash
    rpc_reader :ref_counts
    def ref_counts
      pattern_to_label = {
        "refs/heads/" => :branches,
        "refs/tags/" => :tags,
        "*" => :references
      }

      res = checked_spawn_git!("count-refs", ["--each", "refs/heads/", "refs/tags/", ""])
      res["out"].split("\n").to_h do |l|
        count_pattern = l.split(" ", 2)
        [pattern_to_label.fetch(count_pattern[1]), count_pattern[0].to_i]
      end
    end

    # Public: Fetch the oid of the HEAD ref
    #
    # Returns a sha1
    rpc_reader :read_head_oid
    def read_head_oid
      res = checked_spawn_git!("rev-parse", ["--verify", "--end-of-options", "HEAD"])
      res["out"].chomp
    end

    # Public: Determines if the repository contains at least one branch, at least one tag, or is entirely empty
    #
    # Returns Hash[:empty -> Boolean, :branches -> Boolean, :tags -> Boolean]
    rpc_reader :any_refs
    def any_refs(want_tags: false, want_branches: false)
      refs = {}

      refs[:empty] = !any_refs_kind
      if refs[:empty]
        refs[:branches] = false if want_branches
        refs[:tags] = false if want_tags
      else
        refs[:branches] = any_refs_kind(kind: :branches) if want_branches
        refs[:tags] = any_refs_kind(kind: :tags) if want_tags
      end

      refs
    end

    def any_refs_kind(kind: nil)
      argv = ref_kind_to_args(kind:)
      argv << "-q"
      argv << "--count=1"
      argv << "--end-of-options"

      res = spawn_git("show-ref", argv, nil, {}, nil)
      if res["status"] == 1
        false
      elsif res["ok"]
        true
      elsif res["status"] == 128
        raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
      else
        raise GitRPC::CommandFailed.new(res)
      end
    end

    # Public: Returns the number of branches and/or tags in the repository. Faster than ref_counts since we don't
    # have to enumerate all refs.
    #
    # Returns Hash[:tags -> Integer, :branches -> Integer]
    rpc_reader :branches_and_tags_counts
    def branches_and_tags_counts(want_tags: true, want_branches: true)
      counts = {}
      counts[:branches] = count_ref_kind(kind: :branches) if want_branches
      counts[:tags] = count_ref_kind(kind: :tags) if want_tags
      counts
    end

    private def count_ref_kind(kind:)
      argv = ref_kind_to_args(kind:)
      argv << "--end-of-options"

      res = spawn_git_and_count_stdout_lines("show-ref", argv, {})
      if res["status"] == 1
        0
      elsif res["ok"]
        res["line_count"]
      elsif res["status"] == 128
        raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
      else
        raise GitRPC::CommandFailed.new(res)
      end
    end

    private def ref_kind_to_args(kind:)
      argv = []
      case kind
      when :tags
        argv << "--tags"
      when :branches
        argv << "--heads"
      when nil
        # no args
      else
        raise GitRPC::Error, "Invalid argument kind: #{kind}"
      end
      argv << "--no-check-object-exists"
      argv
    end

    # Public: list branch names and dates the way BranchFinder likes them
    #
    # Returns an array of strings.
    rpc_reader :raw_branch_names_and_dates
    def raw_branch_names_and_dates
      res = spawn_git("for-each-ref",
                      ["--format=%(committerdate:rfc2822)|%(refname)",
                      "--sort=refname:short",
                      "--sort=committerdate",
                      "refs/heads/"])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].split("\n").map { |x| x.split("|", 2) }
    end

    private

    # libgit2 ignores adjacent slashes, i.e. refs///heads///foo is equivalent
    # to refs/heads/foo.  git-show-ref doesn't have the same behavior but we
    # appear to rely on it.  We don't want to wastefully gsub the vast majority
    # of strings that don't do this, so use a heuristic to bail early if possible.
    LIBGIT_COMPAT_TRIGGER = -"//"
    LIBGIT_COMPAT_GSUB_ARGS = [
      %r{/{2,}}, -"/" # replace all instances of more than one slash with one slash
    ]

    def prepare_qualified_refnames_for_git!(refnames)
      refnames.each do |ref|
        # These appear in the output as binary which we match against, so we need
        # to make sure the input is binary as well.
        ref.force_encoding(::Encoding::ASCII_8BIT)

        # Dedupe adjacent slashes if necessary
        if ref.include?(LIBGIT_COMPAT_TRIGGER)
          ref.gsub!(*LIBGIT_COMPAT_GSUB_ARGS)
        end
      end.reject { |ref| ref.include?("\n") }
    end

    # Size of `.git/packed-refs` in bytes
    def packed_refs_size
      File.stat(File.join(path, "packed-refs")).size
    rescue Errno::ENOENT
      # Shouldn't happen in normal operation but might for e.g. new repos
      0
    end
  end
end
