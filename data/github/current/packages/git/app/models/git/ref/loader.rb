# typed: true
# frozen_string_literal: true

# Loader that provides access Git references with built-in memoization.
class Git::Ref::Loader
  include Scientist
  include GitHub::ResilienceMixin

  attr_reader :repository, :rpc, :filter, :cache

  # Public: Builds a ref loader.
  #
  # repository - Repository
  # filter     - Optional. String, filter for refs, either `default`, `extended`, or `nil`.
  #              See `GitRPC::Backend#read_refs` for details.
  #
  # Returns a `Git::Ref::Loader`
  def initialize(repository, filter = nil)
    @repository = repository
    @rpc = repository.rpc
    @filter = filter

    @cache = Git::Ref::Loader::Cache.new
  end

  # Public: Find a ref by qualified name.
  #
  # qualified_name - String, fully qualified ref name.
  #
  # Returns `Git::Ref` or `nil` when no matching ref was found
  def qualified_ref(qualified_name)
    qualified_refs([qualified_name]).first
  end

  # Public: Find refs by qualified names.
  #
  # qualified_names - Array<String>, fully qualified ref names.
  #
  # Returns `Array<Git::Ref>` or `nil` when no matching ref was found
  def qualified_refs(qualified_names)
    unless cache.all_refs?
      missing_names = filter_names(qualified_names).reject do |name|
        cache.ref_cached?(name) || name.nil?
      end

      build_and_cache_ref_data(load_refs(missing_names)) if missing_names.any?
    end

    cache.refs_for(qualified_names)
  end

  # Public: All refs filtered by the provided filter attribute.
  #
  # Returns `Array<Git::Ref>`
  def refs
    return cache.refs if cache.all_refs?

    build_and_cache_ref_data(load_all_refs)

    cache.all_refs!
    cache.refs
  end

  # Public: Total number of references
  #
  # Notice that this method ignores the filter attribute.
  #
  # Returns Integer, or `nil` if operation failed
  def refs_count
    load_ref_counts[:references]
  end

  # Public: Total number of branches (refs starting with `refs/heads/`)
  #
  # Notice that this method ignores the filter attribute.
  #
  # Returns Integer, or `nil` if operation failed
  def branches_count
    branches_and_tags_count[:branches]
  end

  # Public: Total number of tags (refs starting with `refs/tags/`)
  #
  # Notice that this method ignores the filter attribute.
  #
  # Returns Integer, or `nil` if operation failed
  def tags_count
    branches_and_tags_count[:tags]
  end

  def branches_and_tags_count
    return @branches_and_tags_count if defined?(@branches_and_tags_count)
    @branches_and_tags_count = rpc.branches_and_tags_counts
  rescue GitRPC::InvalidRepository, GitHub::DGit::UnroutedError => e
    @branches_and_tags_count = {}
  end

  # Public: Does the repository have any refs?
  #
  # Notice that this method ignores the filter attribute.
  #
  # Returns Boolean
  def has_refs?
    empty = any_refs?[:empty]
    return nil if empty.nil?
    !empty
  end

  # Public: Does the repository have any branches?
  #
  # Notice that this method ignores the filter attribute.
  #
  # Returns Boolean
  def has_branches?
    any_refs?[:branches]
  end

  # Public: Does the repository have any tags?
  #
  # Notice that this method ignores the filter attribute.
  #
  # Returns Boolean
  def has_tags?
    any_refs?[:tags]
  end

  # Public: Consolidates the functionality of has_refs?, has_branches?, and has_tags? in a more performant way
  #
  # Returns Hash[:empty -> Boolean, :branches -> Boolean]
  def any_refs?
    return @any_refs if defined?(@any_refs)
    @any_refs = rpc.any_refs(want_tags: true, want_branches: true)
  rescue GitRPC::InvalidRepository, GitHub::DGit::UnroutedError => e
    @any_refs = {}
  end

  # Public: Notify the loader about an in-memory update of ref.
  #
  # qualified_name - String
  # target         - Target object. Must be a Commit, Tag, Blob, or Tree.
  #                  May also be the String oid of the target object.
  #
  # Returns nothing
  def write_update(qualified_name, target_oid)
    cache.update_ref(qualified_name, build_ref(qualified_name, target_oid))
  end

  private

  def load_ref_counts
    return @ref_counts if defined?(@ref_counts)
    @ref_counts = rpc.ref_counts
  rescue GitRPC::InvalidRepository, GitHub::DGit::UnroutedError => e
    @ref_counts = {}
  end

  def load_refs(qualified_names)
    rpc.read_qualified_refs(qualified_names)
  rescue GitRPC::InvalidRepository, GitHub::DGit::UnroutedError => e
    []
  end

  def load_all_refs
    rpc.read_refs(filter || "all")
  rescue GitRPC::InvalidRepository, GitHub::DGit::UnroutedError => e
    []
  end

  def build_and_cache_ref_data(ref_data)
    ref_data.each do |qualified_name, target_oid|
      next if cache.ref_cached?(qualified_name)
      ref = build_ref(qualified_name, target_oid)
      cache.cache_ref(qualified_name, ref)
    end
  end

  def build_ref(qualified_name, target_oid)
    target_oid ? Git::Ref.new(repository, qualified_name, target_oid) : nil
  rescue TypeError
    # if target_oid is not an OID but rather a symbolic ref, we can't build a ref, so return nil
    nil
  end

  DEFAULT_REF_FILTER = (-> (name) { name =~ GitRPC::Backend::REFS_FILTER }).freeze
  EXTENDED_REF_FILTER = (-> (name) { name !~ GitRPC::Backend::HIDDEN_REFS_FILTER }).freeze

  FILTERS = {
    "default" => DEFAULT_REF_FILTER,
    "extended" => EXTENDED_REF_FILTER,
  }.freeze

  def filter_names(qualified_names)
    return qualified_names unless FILTERS.has_key?(filter)
    qualified_names.select(&FILTERS[filter])
  end

  # Internal: In-memory cache for ref loader
  class Cache
    def initialize
      @refs = {}
      @all_refs = false
    end

    def ref_cached?(qualified_name)
      @refs.has_key?(qualified_name)
    end

    def cache_ref(qualified_name, ref)
      @refs[qualified_name] = ref
    end

    def update_ref(qualified_name, ref)
      if ref.nil? || ref.target_oid == GitHub::NULL_OID
        @refs[qualified_name] = nil
      elsif existing_ref = @refs[qualified_name]
        existing_ref.set_target_object(ref.target_oid)
      else
        cache_ref(qualified_name, ref)
      end
    end

    def refs_for(qualified_names)
      @refs.values_at(*qualified_names)
    end

    def refs
      @refs.values.compact
    end

    def all_refs!
      @all_refs = true
    end

    def all_refs?
      @all_refs
    end
  end
end
