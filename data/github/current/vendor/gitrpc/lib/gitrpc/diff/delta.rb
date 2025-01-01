# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "gitrpc/diff/status_methods"

# A Delta is equivalent to the information received from `git diff-tree`. It describes the changes
# for an individual blob reference in a comparison of the trees of two commits in a repository.
class GitRPC::Diff::Delta

  include GitRPC::Diff::StatusMethods

  SUBMODULE_MODE = "160000".freeze
  SYMLINK_MODE   = "120000".freeze

  def initialize(old_file:, new_file:, status:, similarity:)
    @old_file   = TreeNode.new(**old_file).freeze
    @new_file   = TreeNode.new(**new_file).freeze
    @status     = status.freeze
    @similarity = similarity.to_i
  end

  # The diff status for this tree entry
  attr_reader :status

  # The similarity index of this diff. The similarity is a value between 0 and 100 and only applies to renames.
  attr_reader :similarity

  # The "before" object for this change
  attr_reader :old_file

  # The "after" object for this change
  attr_reader :new_file

  # The paths this delta affects.
  def paths
    [old_file.path, new_file.path]
  end

  def path
    new_file.path
  end

  # Is this a change to a submodule? Or did its type change from/to a submodule?
  def submodule?
    old_file.mode == SUBMODULE_MODE || new_file.mode == SUBMODULE_MODE
  end

  def symlink?
    old_file.mode == SYMLINK_MODE || new_file.mode == SYMLINK_MODE
  end

  # Was the blob in this delta modified?
  def blob_unchanged?
    old_file.oid == new_file.oid
  end

  # Helper for doing a deeper comparison between another GitRPC::Diff::Delta
  # against its status, similarity, old and new file.
  def ==(other)
    other.is_a?(GitRPC::Diff::Delta) && status == other.status && similarity == other.similarity &&
      old_file == other.old_file && new_file == other.new_file
  end

  # Returns the raw diff-tree formatted representation of this delta as a
  # String.
  def to_raw
    raw = ":#{old_file.mode} #{new_file.mode} #{old_file.oid} #{new_file.oid} #{status_raw}\x00#{old_file.path}\x00".b

    if renamed? || copied?
      raw << "#{new_file.path}\x00".b
    end

    raw
  end

  private

  def status_raw
    if renamed? || copied?
      "#{status}#{similarity}"
    else
      status
    end
  end

  class TreeNode
    def initialize(oid:, mode:, path:)
      @oid  = oid.freeze
      @mode = mode.freeze
      @path = path.freeze
    end

    # The blob oid for the content of this object
    attr_reader :oid

    # The mode for this object
    attr_reader :mode

    # The filesystem path for this object
    attr_reader :path

    def ==(other)
      other.is_a?(GitRPC::Diff::Delta::TreeNode) && oid == other.oid && mode == other.mode && path == other.path
    end
  end
end
