# typed: true
# frozen_string_literal: true

module GitHub
  # Documents and classifies all the different types of git refs.
  module RefType
    extend self

    # Internal: Map ref patterns to symbol type.
    REF_TYPE_PATTERNS = {
      # User branches
      "refs/heads/*" => :branch,

      # User tags
      "refs/tags/*" => :tag,

      # User git-notes
      "refs/notes/*" => :notes,

      # Network remote tracking branches
      "refs/remotes/*" => :remote_tracking,

      # User visible, but not user writable PR head tracking ref
      "refs/pull/*/head" => :pull_head,

      # Internal PR tracking chain for all heads
      "refs/__gh__/pull/*/heads" => :pull_heads,

      # User visible, but not user writable computed merge commit for PR
      "refs/pull/*/merge" => :pull_merge,

      # Internal temp ref created by git-fetch-commits
      "refs/__gh__/temp/*" => :temp,

      # Deprecated temp ref created by git-fetch-commits
      "refs/__temp__/*" => :temp,

      # User visible, but not user writable refs
      "refs/gh/queue/*" => :merge_queue,

      # Everything else under __gh__ is internal
      "refs/__gh__/*" => :internal,

      # Anything else the user pushes up
      "*" => :user,
    }.freeze

    # Public: Array of all valid ref type Symbols
    REF_TYPES = REF_TYPE_PATTERNS.values.freeze

    # Public: Detect the type of a git ref name.
    #
    # ref - String of fully qualified ref name
    #
    # Returns Symbol in REF_TYPE set.
    def detect_ref_type(ref)
      if match = REF_TYPE_PATTERNS.detect { |(m, _)| File.fnmatch(m, ref) }
        match[1]
      end
    end
  end
end
