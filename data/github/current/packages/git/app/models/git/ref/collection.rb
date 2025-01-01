# typed: true
# frozen_string_literal: true

require "branch_sorter"

# Collection for accessing Git references efficiently.
class Git::Ref::Collection
  # TODO Eventually we want to eliminate all complete `read_refs` calls.
  #   It's too expensive to load all refs into memory when a repository
  #   has tens of thousands of them.
  #
  #   To replace the `Enumerable` interface, we need to build a way to
  #   request subsets (pages) of refs on the GitRPC backend. Such pages
  #   might have a search string or a page number as an input.
  include Enumerable

  extend T::Sig

  include Git::Ref::Collection::Pagination

  attr_reader :loader, :repository, :prefix, :order, :branch_sort

  # Public: Builds a ref collection using the provided ref loader.
  #
  # loader      - A `Git::Ref::Loader` instance
  # prefix      - String limiting the scope of accessed refs, e.g. `refs/heads/`
  # order       - Symbol indicating the order, either `:asc` or `:desc`
  # branch_sort - Boolean indicating whether to use branch sorter
  #
  # Returns a `Git::Ref::Collection`
  def initialize(loader:, prefix: nil, order: :asc, branch_sort: true)
    @loader = loader
    @repository = loader.repository
    @prefix = prefix
    @order = order
    @branch_sort = branch_sort
  end

  # Public: Find a ref by name.
  #
  # This first checks for a fully qualified name ("refs/heads/master")
  # before falling back on the heads and tags hierarchies for short name
  # matches. "foobar" matches "refs/heads/foobar" before "refs/tags/foobar".
  #
  # name - String ref name. May be fully qualified or a short name.
  #
  # Returns `Git::Ref` or nil when no matching ref was found
  def find(name)
    async_find(name).sync
  end
  alias [] find

  def async_find(name)
    return Promise.resolve(nil) unless name

    candidate_promises = ref_name_candidates_for(name).map do |candidate|
      Platform::Loaders::Ref.load(loader, candidate)
    end

    Promise.all(candidate_promises).then do |refs|
      ref = refs.find(&:present?)
      rebuild_with_same_prefix(ref)
    end
  end

  # Public: Find all refs by fully qualified names.
  #
  # qualified_names - Array<String> of ref names
  #
  # Returns Array<Git::Ref>, can include `nil` when no matching ref was found.
  def find_all(qualified_names)
    return [] if qualified_names.empty?

    # TODO Make this work with unqualified names too
    loader.qualified_refs(qualified_names).map do |ref|
      rebuild_with_same_prefix(ref)
    end
  end

  # Public: Iterate over all `Git::Ref` objects in sorted order.
  #
  # The sorting is determined by the `order` and `branch_sort` attributes.
  #
  # Notice: This loads the complete list of refs into memory.`
  #
  # Yields `Git::Ref` objects to the block for each ref.
  def each(&block)
    sorted_refs.each(&block)
  end

  # Public: The short names of all refs in sorted order.
  #
  # The sorting is determined by the `order` and `branch_sort` attributes.
  #
  # Notice: This loads the complete list of refs into memory.`
  #
  # Returns Array<String>
  def names
    map(&:name)
  end

  # Public: Returns the default branch short name
  def default
    # nb: repository.default_branch is not memoized so we memoize it here
    @default_branch ||= repository.default_branch
  end

  # Public: The short names of all refs in sorted order with the
  # default_branch returned first.
  #
  # The sorting is determined by the `order` and `branch_sort` attributes.
  #
  # Notice: This loads the complete list of refs into memory.`
  #
  # Returns Array<String>
  def refs_with_default_first
    sort_by { |ref| ref.name == default ? 0 : 1 }
  end

  # Public: Find a ref, bypassing the any cache.
  #
  # This is identical to `#find` but is recommended in situations where
  # you're modifying a ref and therefore need an as-consistent-as-possible
  # view of the ref state in the repository.
  #
  # name - String ref name. May be fully qualified or a short name.
  #
  # Returns `Git::Ref` or `nil` when no matching ref was found.
  def read(name)
    target_oid = repository.rpc.rev_parse(extend_with_prefix(name), use_cache: false)
    build(name, target_oid)
  end

  # Public: Check if a ref exists.
  #
  # name - String ref name. May be fully qualified or a short name.
  #
  # Returns Boolean
  sig { params(name: T.nilable(String)).returns(T::Boolean) }
  def exist?(name)
    find(name).present?
  end
  alias include? exist?

  # Public: Build a new ref object associated with the repository.
  #
  # This doesn't create the ref in the underlying Git repository and it's not yet
  # part of any ref collection. The `#create` or `#update` method can be called
  # on the `Git::Ref` object to actually write the ref.
  #
  # name   - String ref name. Must be fully qualified when no prefix is
  #          in effect. May be a short name if a prefix is set.
  # target - Optional. Target object. Must be a Commit, Tag, Blob, or Tree.
  #          May also be the String oid of the target object.
  #
  # Returns `Git::Ref`
  def build(name, target = nil)
    Git::Ref.new(repository, name, target, prefix)
  end

  # Public: Find ref with the given name or build a new ref otherwise.
  #
  # name - String ref name. May be fully qualified or a short name.
  #
  # Returns `Git::Ref`
  def find_or_build(name)
    find(name) || build(name)
  end

  # Public: Create ref in the underlying repository.
  #
  # name    - String ref name. Must be fully qualified when no prefix is
  #           in effect. May be a short name if a prefix is set.
  # target  - Optional. Target object. Must be a Commit, Tag, Blob, or Tree.
  #           May also be the String oid of the target object.
  # author  - The User creating the ref
  # options - Options hash with additional settings related to the reflog,
  #           cache, and processing background jobs. See `Git::Ref#create`.
  #
  # Returns `Git::Ref`
  def create(name, target, author, options = {})
    build(name).create(target, author, options)
  end

  # Public: Total number of refs part of the collection
  #
  # Returns Integer
  def size
    case prefix
    when nil
      loader.refs_count
    when "refs/heads/"
      loader.branches_count
    when "refs/tags/"
      loader.tags_count
    else
      count
    end
  end

  # Public: Checks whether there are any refs in the collection
  #
  # Returns Boolean
  def empty?
    !any?
  end

  # Public: Checks whether there are any refs in the collection
  #
  # Returns Boolean
  def any?
    case prefix
    when nil
      loader.has_refs?
    when "refs/heads/"
      loader.has_branches?
    when "refs/tags/"
      loader.has_tags?
    else
      super
    end
  end

  # Public: Reverse the sort order when enumerating or paging in place.
  #
  # Returns `Git::Ref::Collection`
  def reverse!
    @order = (order == :desc ? :asc : :desc)
    @sorted_refs.reverse! if defined?(@sorted_refs)
    self
  end

  # Public: Filter the refs collection down to those matching the starting pattern.
  #
  # This method includes the prefix provided in the `prefix` attribute.
  #
  # pattern - String to use for matching refs from the start.
  #
  # Returns new `Git::Ref::Collection` selecting only refs that match pattern.
  def filter(pattern, order: nil)
    order ||= @order

    self.class.new(
      loader: loader,
      prefix: extend_with_prefix(pattern),
      order: order,
      branch_sort: branch_sort,
    )
  end

  # Public: Filter the in-memory set of tags by the given substring
  #
  # Returns array of Git::Ref selecting only refs contain the given substring
  def substring_filter(substring:, limit: 100, case_sensitive: true)
    substring = substring.b

    if case_sensitive
      lazy.select { |ref| ref.name.include?(substring) }.take(limit).to_a
    else
      lazy.select { |ref| ref.name.downcase.include?(substring) }.take(limit).to_a
    end
  end

  # Public: Notify the collection about a ref update.
  #
  # Calls to this method only update in-memory caches.
  #
  # qualified_name - String
  # target         - Target object. Must be a Commit, Tag, Blob, or Tree.
  #                  May also be the String oid of the target object.
  #
  # Returns nothing
  def write_update(qualified_name, target_oid)
    loader.write_update(qualified_name, target_oid)
  end

  def temp_name(topic: "temp", prefix: "")
    num  = 1
    sep  = "-"
    base = (prefix.length > 0 ? prefix + sep : "") + topic
    name = base + sep + num.to_s
    while include?(name)
      num += 1
      name = base + sep + num.to_s
    end
    name
  end

  # Public: Returns whether a branch and tag with the same name exist
  #
  # name - String unqualified ref name
  #
  # Returns Boolean - true if collision exists, false otherwise
  def unqualified_name_conflict?(name)
    unqualified_name_conflicts([name]).present?
  end

  # Public: Returns all the names in the given array of ref names where a branch
  # and tag with that same name exist
  #
  # name - Array of String unqualified ref name
  #
  # Returns an Array of String ref names of branch/tag collisions
  def unqualified_name_conflicts(names)
    branch_and_tags = names.flat_map do |name|
      ["refs/heads/#{name}", "refs/tags/#{name}"]
    end

    refs_by_name = find_all(branch_and_tags).compact.group_by(&:name)
    refs_by_name.delete_if { |_name, refs| refs.size <= 1 }
    refs_by_name.keys
  end

  # Public: Load target objects for all given refs efficiently.
  #
  # After this method, all `Git::Ref#target` objects will be present.
  # In addition, any ref pointing at an annotated tag object will have its
  # target object preloaded as well. Worst case this method makes two round
  # trips to each of the cache and RPC layers.
  #
  # refs - Array<Git::Ref>
  #
  # Returns nothing
  def self.preload_target_objects(refs)
    return refs if refs.empty?

    repository = refs.first.repository
    raise ArgumentError.new("all refs need to belong to same repository") if refs.any? { |ref| ref.repository != repository }

    oids = refs.map { |ref| ref.target_oid }.uniq
    objects = repository.objects.read_all(oids, skip_bad: true).index_by(&:oid)

    second_pass = []
    refs.each do |ref|
      object = objects[ref.target_oid]
      ref.set_target_object(object)
      second_pass << object if object.is_a?(::Tag) && ref.is_a?(::Git::Ref)
    end

    preload_target_objects(second_pass)
  end

  # Public: qualify tag names with refs/tags/ prefix
  #
  # tag_names - Array of unqualified tag names
  #
  # Returns array of qualified tag names, skipping any nil or empty names in the input array
  def self.qualify_tag_names(tag_names)
    tag_names.filter_map { |name| "refs/tags/#{name}" if name.present? }
  end

  private

  def sorted_refs
    return @sorted_refs if defined?(@sorted_refs)

    refs = loader.refs.dup
    refs.select! { |ref| ref.qualified_name.starts_with?(prefix) } if prefix

    refs_by_qualified_names = refs.index_by(&:qualified_name)
    qualified_names = refs_by_qualified_names.keys

    sorted_qualified_names = sort_names(qualified_names)

    @sorted_refs = sorted_qualified_names.map do |name|
      rebuild_with_same_prefix(refs_by_qualified_names[name])
    end
  end

  def sort_names(qualified_names)
    qualified_names = branch_sort_names(qualified_names) if branch_sort

    if order == :asc
      qualified_names
    else
      qualified_names.reverse
    end
  end

  def branch_sort_names(names)
    sanitizer = prefix ? proc { |name| name[prefix.size..-1] } : nil
    BranchSorter.new(names, &sanitizer).to_a
  end

  def ref_name_candidates_for(name)
    ref_name_candidates = []

    if prefix
      ref_name_candidates << name.b if name.starts_with?(prefix)
      ref_name_candidates << "#{prefix}#{name}".b
    else
      ref_name_candidates << name.b << "refs/heads/#{name}".b << "refs/tags/#{name}".b

    end

    ref_name_candidates
  end

  def extend_with_prefix(suffix)
    suffix = suffix.try(:b)

    if suffix.nil?
      prefix
    elsif prefix.nil? || suffix.start_with?(prefix)
      suffix
    else
      "#{prefix}#{suffix}".b
    end
  end

  def rebuild_with_same_prefix(ref)
    return ref if ref.nil? || ref.prefix == prefix

    build(ref.qualified_name, ref.target_oid)
  end
end
