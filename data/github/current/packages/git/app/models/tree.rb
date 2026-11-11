# typed: true
# frozen_string_literal: true

# Git Tree object. Eventual home for all app-level tree related behavior.
#
# NOTE This is largely just a stub right now. The tree accessors are not fleshed
# out. RepositoryObjectsCollection relies on a model being available to represent
# git object data.
#
# Read 🌳 s from the repository:
#
#     repository = Repository.with_name_with_owner("great/repo")
#     tree = repository.objects.read('deadbee...')
#
# The tree's info hash has this structure:
#
#    { 'type'    => 'tree',
#      'oid'     => string sha1,
#      'entries' => { tree entries hash } }
#
# The tree entries hash includes one item for each tree entry. The key
# is the name of the tree entry and values have this structure:
#
#    { 'type'   => string entry type - 'tree' or 'blob',
#      'oid'    => string entry oid,
#      'mode'   => integer file mode,
#      'name'   => string file name }
#
# Only the oid is exposed as an attribute currently.
class Tree
  # The root path of a git tree is an empty string.  Referring to this
  # constant is clearer than a literal "".
  ROOT_PATH = "".freeze

  # The repository this tree belongs to.
  attr_reader :repository

  # The Tree's git object id. 40 character SHA1 strings only.
  attr_reader :oid

  attr_reader :entries

  # Create a new Tree.
  #
  # repository - The owning Repository object.
  # info       - Hash of tree attributes.
  #
  def initialize(repository, info = {})
    @repository = repository
    @oid = info["oid"]
    @entries = (info["entries"] || {}).values.map { |info| TreeEntry.new(repository, info) }
  end

  def abbreviated_oid
    oid && oid[0, Commit::ABBREVIATED_OID_LENGTH]
  end

  include GitHub::Relay::GlobalIdentification

  def global_id
    "#{repository.id}:#{oid}"
  end

  # This is here to satisfy an interface implemented by all git object model
  # classes. The only interesting implementation is in Tag and Commit, since
  # there's no way to peel a tree to anything, let alone a commit.
  def peel_to_commit
    nil
  end
end
