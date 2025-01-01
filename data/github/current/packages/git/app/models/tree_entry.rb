# typed: true
# frozen_string_literal: true

require "cache_key_logging_denylist"

class TreeEntry
  MD_EXTENSIONS = Set.new(%w[.md .mkdn .mkd .mdown .markdown .mdx]).freeze

  include Linguist::BlobHelper
  include TreeEntryRenderHelper

  include GitHub::UTF8

  attr_reader :info, :repository

  # The submodule object if this is a submodule
  attr_accessor :submodule

  # Is this blob being used as a gist snippet
  attr_writer :snippet

  # String ref name associated with this tree entry
  attr_accessor :ref_name

  # String prefix to prepend to the path
  attr_accessor :path_prefix

  def initialize(repo, info)
    @repository = repo
    @info = info
    self.data = info["data"] if info.key?("data")
    @language = info["language"] if info.key?("language")
  end

  def self.load(*args)
    T.unsafe(self).new(*args)
  end

  def self.from_ls_tree(repo, entry, from_collection:)
    mode, type, oid, size, path = entry

    size = nil if size == "-"

    new(repo, {
      "mode" => mode,
      "type" => type,
      "oid"  => oid,
      "size" => size && size.to_i,
      "path" => path,
      "collection" => from_collection,
    })
  end

  def async_repository
    Promise.resolve(repository)
  end

  def [](key)
    if info.key?(key.to_s)
      send(key.to_sym)
    end
  end

  def type
    info["type"]
  end

  def oid
    info["oid"]
  end
  alias id oid
  alias sha oid

  def ==(other)
    self.class == other.class &&
      oid == other.oid
  end

  def name
    info["path"] ? File.basename(info["path"]) : info["name"]
  end
  alias to_s name

  def display_name
    name = self.name
    if name.encoding == ::Encoding::UTF_8 && name.valid_encoding?
      name
    else
      utf8(name)
    end
  end

  def symlink_target_oid
    info["symlink_target"]
  end

  def simplified_path
    info["simplified_path"]
  end
  alias simplified_path? simplified_path

  def simplified_utf8_path
    path = simplified_path
    if path.encoding == ::Encoding::UTF_8 && path.valid_encoding?
      path
    else
      utf8(path)
    end
  end

  # Public: Resolve the TreeEntry as its symlink target.
  #
  # Return self if the TreeEntry is not a symlink.
  #
  # Constructs a TreeEntry pointing at the target of the symlink,
  # with a path matching the current TreeEntry object.
  #
  # NOTE: This method may return surprising results based on
  # how the TreeEntry was fetched from GitRPC. For example, if the
  # symlink points above the directory hierachy from where the
  # TreeEntry was fetched, its target won't be present and self
  # will be returned.
  #
  # Returns a TreeEntry.
  def resolve_symlink
    return self unless symlink?
    return self unless symlink_target
    self.class.new(repository, info["symlink_target_object"]).tap do |target|
      target.symlink_source = self
      target.info["path"] = path
    end
  end

  # True if this file is a symlink which does not directly resolve to a file in the repo
  def unresolvable_symlink?
    # Not a symlink
    return false if !symlink?

    # Didn't resolve on the backend
    return true if !symlink_target_oid

    # Points to another symlink
    return true if symlink_target.symlink?

    # Doesn't point to a blob
    return true if !symlink_target.blob?

    # Resolves to a file
    false
  end

  def size
    git_lfs_size || object_size || 0
  end

  # The size of the object in Git.
  def object_size
    info["size"]
  end

  # Public: Determines if the file is executable for anyone.
  #
  # Returns a Boolean.
  def executable?
    mode_str = mode # e.g., "100755"
    return false unless mode_str.present?

    ugo = mode_str.slice(3, 6) # User, Group, Other permissions, e.g., "755"
    return false unless ugo.present?

    ugo.split("").map(&:to_i).any?(&:odd?)
  end

  def blob?
    type == "blob"
  end

  def submodule?
    type == "commit"
  end

  def tree?
    type == "tree"
  end
  alias directory? tree?

  def markdown?
    MD_EXTENSIONS.include?(extension&.downcase)
  end

  def valid_but_unparsable_citation_file?
    path == "inst/CITATION" || path =~ PreferredFile::UNPARSABLE_CITATION_REGEXP
  end

  def path
    if path_prefix.present?
      File.join(@path_prefix, info["path"])
    else
      info["path"]
    end
  end

  def path_raw
    path.b
  end

  def display_path
    path = self.path
    if path.encoding == ::Encoding::UTF_8 && path.valid_encoding?
      path
    else
      utf8(path)
    end
  end

  def mode
    return unless info.has_key?("mode")
    case info["mode"]
    when Integer
      info["mode"].to_s(8)
    when String
      info["mode"]
    end
  end

  def symlink?
    mode && mode[0..1] == "12"
  end

  def truncated?
    info["truncated"]
  end

  def size_over_limit?
    info["size_over_limit"]
  end

  # Override Linguist::BlobHelper's implementation to just return binary or
  # UTF-8, since we transcode all non-binary data to UTF-8 in our #data=
  # method.
  def detect_encoding
    @detect_encoding ||= begin
      # Make sure our data has been loaded so we know whether it's binary or
      # not.
      self.data

      if info["binary"]
        { type: :binary, confidence: 100 }
      else
        GitHub::Encoding::VALID_UTF8
      end
    end
  end

  def transcoding_necessary?
    !binary? && detected_encoding != GitHub::Encoding::UTF8
  end

  def detected_encoding
    info["encoding"]
  end

  def formatted?
    return @_formatted if defined?(@_formatted)

    log_cache_hit = T.let(true, T::Boolean)
    attr_key = Digest::SHA256.hexdigest(attributes.sort.join(":")) if attributes.any?
    @_formatted = GitHub.cache.fetch(["tree_entry:formatted", name, oid, attr_key].compact.join(":")) do
      # if we're here, the cache missed
      log_cache_hit = false
      GitHub.dogstats.increment("cache.miss", tags: ["action:tree_entry.formatted"])
      # if we hit this a bunch, we may want to preload via memcache multiget
      self.can_render?
    end

    if log_cache_hit
      GitHub.dogstats.increment("cache.hit", tags: ["action:tree_entry.formatted"])
    end

    @_formatted
  end
  alias prose? formatted?

  # Public: Does this TreeEntry represent a plaintext file?
  #
  # Plaintext is defined as a text file that won't be rendered
  # as markup.
  #
  # Returns a Boolean.
  def plaintext?
    !binary? && !formatted?
  end

  def has_unix_line_endings?
    if !defined? @has_unix_line_endings
      @has_unix_line_endings = self.data =~ /(^|[^\r])\n/
    end
    @has_unix_line_endings
  end

  def has_windows_line_endings?
    if !defined? @has_windows_line_endings
      @has_windows_line_endings = self.data =~ /\r\n/
    end
    @has_windows_line_endings
  end

  def has_only_unix_line_endings?
    has_unix_line_endings? && !has_mixed_line_endings?
  end

  def has_only_windows_line_endings?
    has_windows_line_endings? && !has_unix_line_endings?
  end

  def has_mixed_line_endings?
    has_unix_line_endings? && has_windows_line_endings?
  end

  # Public: Does this TreeEntry represent an open source license file?
  #
  # Returns a Boolean.
  def license?
    blob? && (Licensee::ProjectFiles::LicenseFile.name_score(name.to_s) > 0)
  end

  def from_collection?
    info["collection"]
  end

  alias object_text? text?

  def text?
    !git_lfs? && object_text?
  end

  def data
    async_data.sync
  end

  def data=(raw_blob_data)
    @async_data = Promise.resolve(transcode(raw_blob_data.dup))
    @async_raw_data = Promise.resolve(raw_blob_data)
  end

  def async_data
    return @async_data if defined?(@async_data)
    return @async_data = Promise.resolve(nil) unless blob? && oid

    @async_data = Platform::Loaders::BlobInformation.load(repository, oid).then do |info|
      if info
        @info.merge!(info)
        transcode(@info["data"])
      end
    end
  end

  def raw_data
    async_raw_data.sync
  end

  def async_raw_data
    return @async_raw_data if defined?(@async_raw_data)
    return @async_raw_data = Promise.resolve(nil) unless blob? && oid

    @async_raw_data = Platform::Loaders::BlobInformation.load(repository, oid).then do |info|
      if info
        @info.merge!(info)
        @info["data"]
      end
    end
  end

  NEWLINE_REGEXP = Regexp.union(["\r\n", "\r", "\n"])

  def self.split_lines(data)
    data.chomp.split(NEWLINE_REGEXP, -1)
  end

  def lines
    @lines ||= begin
                 if data
                   TreeEntry.split_lines(data)
                 else
                   []
                 end
               end
  end

  def line_count_cache_key
    @line_count_cache_key ||= "TreeEntry:line_count:#{self.oid}"
  end

  def line_count!
    return nil unless data && lines
    count = data.scan(NEWLINE_REGEXP).count
    count += 1 unless data.end_with?("\r\n", "\r", "\n")
    count
  end

  def line_count
    return @line_count if defined?(@line_count)
    return unless blob?
    @line_count = GitHub.cache.fetch(line_count_cache_key) { line_count! }
  end

  # Returns the current number of lines of code in the blob. If the blob is truncated,
  # appends "+" to the end.
  def truncated_loc
    if truncated?
      "#{loc}+"
    else
      loc.to_s
    end
  end

  # Returns the current number of source lines of code in the blob. If the blob is truncated,
  # appends "+" to the end.
  def truncated_sloc
    if truncated?
      "#{sloc}+"
    else
      sloc.to_s
    end
  end

  attr_writer :line_count

  # Load the line counts for an array of TreeEntry objects
  #
  # The line counts will first be multi-get from cache; if
  # not found, a batch read will be performed through GitRPC
  #
  # repository - the repository to which all entries belong
  # entries - an Array of TreeEntry objects
  #
  # Returns nothing; all the entries are updated in-place
  def self.load_line_counts!(repository, entries)
    entries = entries.select { |entry| entry.blob? }
    cache_keys = entries.map { |blob| blob.line_count_cache_key }
    cached_loc = GitHub.cache.get_multi(cache_keys)

    lookup = entries.map { |blob| blob.oid unless cached_loc.include?(blob.line_count_cache_key) }
    lookup.compact!
    rpc_loc = repository.rpc.count_lines(lookup)

    entries.each do |blob|
      cache_key = blob.line_count_cache_key
      loc = cached_loc[cache_key]
      loc ||= GitHub.cache.fetch(cache_key, force: true) { rpc_loc[blob.oid] }

      blob.line_count = loc
    end
  end

  attr_writer :attributes

  def attributes
    return @attributes if instance_variable_defined?(:@attributes)

    @attributes = {}
  end

  # Public: Load attributes for given set of entries and commit
  #
  # entries    - Array of TreeEntry objects
  # commit_oid - Commit OID String
  #
  # Returns nothing; all the entries are updated in-place
  def self.load_attributes!(entries, commit_oid)
    Promise.all(entries.map { |entry| entry.async_attributes(commit_oid) }).sync
  end

  def async_attributes(commit_oid)
    return @async_attributes if defined?(@async_attributes)
    @async_attributes = Platform::Loaders::GitAttribute.load(repository, path_raw, commit_oid).then do |attributes|
      @attributes = attributes
    end
  end

  # Public: Is the blob in a documentation directory?
  #
  # Documentation files are ignored by language statistics.
  #
  # This overwrites `Linguist::BlobHelper#documentation?` and uses
  # the value from Git attributes first before falling back to the
  # default implementation.
  #
  # Returns Boolean
  def documentation?
    if !attributes["linguist-documentation"].nil?
      boolean_attribute(attributes["linguist-documentation"])
    else
      super
    end
  end

  # Public: Is the blob a generated file?
  #
  # Generated source code is suppressed in diffs and is ignored by
  # language statistics.
  #
  # May load Blob#data
  #
  # This overwrites `Linguist::BlobHelper#generated?` and uses
  # the value from Git attributes first before falling back to the
  # default implementation.
  #
  # Returns Boolean
  def generated?
    if !attributes["linguist-generated"].nil?
      boolean_attribute(attributes["linguist-generated"])
    else
      super
    end
  end

  def async_generated?(commit_oid)
    async_attributes(commit_oid).then { |_attrs| generated? }
  end

  # Public: Is the blob in a vendored directory?
  #
  # Vendored files are ignored by language statistics.
  #
  # This overwrites `Linguist::BlobHelper#vendored?` and uses
  # the value from Git attributes first before falling back to the
  # default implementation.
  #
  # Returns Boolean
  def vendored?
    if !attributes["linguist-vendored"].nil?
      boolean_attribute(attributes["linguist-vendored"])
    else
      super
    end
  end

  # Public: Detects the Language of the blob.
  #
  # May load Blob#data
  #
  # This overwrites `Linguist::BlobHelper#language` and uses
  # the value from Git attributes first before falling back to the
  # default implementation.
  #
  # Returns a Linguist::Language or nil if none is detected
  def language
    return @language if defined?(@language)

    @language = if lang = attributes["linguist-language"]
      Linguist::Language.find_by_alias(lang)
    else
      super
    end
  end

  # Public: The configured or detected encoding name of the blob.
  #
  # This overwrites `Linguist::BlobHelper#encoding` and uses the value from Git
  # attributes first before falling back to the default implementation - which
  # is to detect the encoding name.
  #
  # Returns the encoding name as a String.
  def encoding
    return @encoding if defined?(@encoding)

    @encoding = if encoding = attributes["linguist-encoding"]
      encoding
    else
      super
    end
  end

  # Public: The Ruby-compatible encoding name of the blob.
  #
  # This overwrites `Linguist::BlobHelper#ruby_encoding` and uses the value from
  # the #encoding method here first before falling back to the default
  # implementation.
  #
  # Returns the encoding name as a String.
  def ruby_encoding
    return @ruby_encoding if defined?(@ruby_encoding)

    @ruby_encoding = Encoding.find(encoding).name
  rescue ArgumentError
    super
  end

  # Returns true if the attribute is present and not "false".
  def boolean_attribute(attribute)
    attribute.to_s != "false"
  end

  def symlink_target
    return @target if defined?(@target)
    return if !symlink? || !symlink_target_oid

    @target = self.class.new(repository, info["symlink_target_object"]).tap do |target|
      target.symlink_source = self
    end
  end

  attr_accessor :symlink_source

  def extension
    utf8(File.extname(name))
  end
  alias extname extension

  # The entries in this tree
  #
  # Returns an Array of tree entries
  def tree_entries
    if tree?
      @tree_entries ||= repository.tree_entries(oid, "")
    else
      []
    end
  end

  def large?
    if git_lfs?
      super
    else
      truncated? && data.blank?
    end
  end

  # Parses the Git LFS pointer meta data.
  def git_lfs_pointer
    return @git_lfs_pointer if defined?(@git_lfs_pointer)
    return if from_collection?
    return unless object_text?

    @git_lfs_pointer = Media::Blob.pointer(data)
  end

  # Gets the Git LFS oid.
  #
  # Returns a String oid, or nil.
  def git_lfs_oid
    git_lfs_pointer.try(:oid)
  end

  # Returns the Media::Blob for this Git LFS pointer.  Note: A Git LFS pointer
  # in a Repository does not mean it contains the object.  Anyone can write a
  # blob.  A Media::Blob is created on a successful Git LFS push, so GitHub
  # authorization has been verified.  It also verifies that the uploaded file's
  # sha-256 hash matches the OID.
  def git_lfs_blob
    return @git_lfs_blob if defined?(@git_lfs_blob)

    @git_lfs_blob =
      if (oid = @repository.git_lfs_enabled? && git_lfs_oid).present?
        Media::Blob.fetch(@repository, oid)
      end
  end

  # Returns the Integer size of the actual Git LFS object.  If the pointer does
  # not have the size, then look up the Media::Blob from the OID and check
  # that.
  def git_lfs_size
    return unless p = git_lfs_pointer
    return p.size if p.size > 0
    git_lfs_blob.try(:size)
  end

  # Returns true if the TreeEntry is a Git LFS pointer AND the OID matches a
  # Media::Blob for the current Repository.
  def git_lfs?
    !!git_lfs_blob
  end

  # Returns ture if the TreeEntry is a Git LFS pointer.  It doesn't necessarily
  # mean the Repository contains the object, since anything can write a blob.
  # See #git_lfs? or #git_lfs_blob.
  def git_lfs_pointer?
    !!git_lfs_pointer
  end

  # Submodule methods
  def submodule_git_url
    submodule? && submodule && submodule.url
  end

  def submodule_hosted_on_github?
    submodule? && submodule && submodule_user && submodule_repo
  end

  def submodule_user
    submodule? && submodule && submodule.user
  end

  def submodule_repo
    submodule? && submodule && submodule.repo
  end

  # Syntax-highlights a blob.
  #
  # strategy        - :from_cache_only
  #                   Returns from cache or `nil` nil if no precomputed result is found.
  #                 - :from_cache_or_plain
  #                   Returns from cache or plain lines if no precomputed result is found.
  #                 - nil
  #                   Performs highlighting and updates the cache if no precomputed result is found
  #
  # Returns an Array of HTML Strings, one for each line in the blob. If the
  # blob cannot be highlighted, the (HTML-escaped) lines of the blob are
  # returned.
  def colorized_lines(strategy: nil)
    # Return the memoized value if available
    return @colorized_lines if defined?(@colorized_lines)

    cached = GitHub.cache.get(colorized_lines_cache_key)

    unless cached.nil?
      GitHub.dogstats.increment("cache.hit", tags: ["action:tree_entry.colorized_lines"])
      return @colorized_lines = cached
    end

    GitHub.dogstats.increment("cache.miss", tags: ["action:tree_entry.colorized_lines"])

    return nil if strategy == :from_cache_only
    return highlight_plain_lines if strategy == :from_cache_or_plain

    start = GitHub::Dogstats.monotonic_time
    stats_prefix = "blob.process.#{GitHub::Colorize.stats_key}"

    lines = T.let(nil, T.nilable(T::Array[String]))
    should_cache = T.let(true, T::Boolean)
    if safe_to_colorize? && tm_scope
      Failbot.push("gh.repo.blob.path": path, "gh.repo.blob.size": size, "gh.repo.blob.oid": oid) do
        begin
          lines = GitHub::Colorize.highlight_one(tm_scope, data, fallback_to_plain: false)
        rescue GitHub::Colorize::RPCError
          should_cache = false
        end
      end
    end

    if lines
      GitHub.dogstats.timing_since("#{stats_prefix}.success", start)
    else
      lines = GitHub::Colorize.highlight_plain(data)
      GitHub.dogstats.timing_since("#{stats_prefix}.error", start)
    end

    GitHub.dogstats.timing("#{stats_prefix}.highlighted_bytesize", lines.sum { |l| l.bytesize })

    set_colorized_lines(lines) if should_cache
    @colorized_lines = lines
    @colorized_lines
  end

  def styling_directives(strategy: nil)
    # Return the memoized value if available
    return @styling_directives if defined?(@styling_directives)

    cached = GitHub.cache.get(styling_directives_cache_key_short_code)

    unless cached.nil?
      GitHub.dogstats.increment("cache.hit", tags: ["action:tree_entry.styling_directives"])
      return @styling_directives = cached
    end

    GitHub.dogstats.increment("cache.miss", tags: ["action:tree_entry.styling_directives"])

    return nil if strategy == :from_cache_only || strategy == :from_cache_or_plain

    start = GitHub::Dogstats.monotonic_time
    stats_prefix = "blob.process.#{GitHub::Colorize.stats_key}.styling_directives"

    directives = T.let(nil, T.nilable(T::Array[T::Array[String]]))
    should_cache = T.let(true, T::Boolean)
    if safe_to_colorize? && tm_scope
      Failbot.push("gh.repo.blob.path": path, "gh.repo.blob.size": size, "gh.repo.blob.oid": oid) do
        begin
          directives = GitHub::Colorize.styling_directives(tm_scope, data, fallback_to_plain: false)
        rescue GitHub::Colorize::RPCError
          should_cache = false
        end
      end
    end

    if directives
      GitHub.dogstats.timing_since("#{stats_prefix}.success", start)
    else
      directives = GitHub::Colorize.styling_directives_plain(data)
      should_cache = false
      GitHub.dogstats.timing_since("#{stats_prefix}.error", start)
    end

    set_styling_directives(directives) if should_cache
    @styling_directives = directives
    @styling_directives
  end

  def highlight_plain_lines
    return @plain_lines if defined?(@plain_lines)
    @plain_lines = GitHub::Colorize.highlight_plain(data)

    @plain_lines
  end

  def async_colorized_lines
    Platform::Loaders::Cache.load(colorized_lines_cache_key).then do |cached_colorized_lines|
      next cached_colorized_lines if cached_colorized_lines

      Platform::Loaders::TreeEntryColorizedLines.load(self).then do |colorized_lines|
        if colorized_lines
          # Write to the cache, but only if we have a colorization result
          set_colorized_lines(colorized_lines)
          colorized_lines
        else
          lines = force_escape_with_transcoding_guess(data).split("\n", -1)
          lines.pop if !lines.empty? && lines.last.empty?
          lines.map(&:html_safe)
        end
      end
    end
  end

  def async_file_lines
    async_colorized_lines.then do |colored_lines|
      colored_lines.each_with_index.map do |line, index|
        {
          html: line,
          number: index + 1,
        }
      end
    end
  end

  def set_colorized_lines(result)
    # Remove the last incomplete line if the blob was truncated.
    # This allows it to show up in its complete, unhighlighted form later.
    result.pop if truncated? && !data.end_with?("\n")

    GitHub.cache.set(colorized_lines_cache_key, result, 0, false)
    result
  end

  def set_styling_directives(result)
    # Remove the last incomplete line if the blob was truncated.
    # This allows it to show up in its complete, unhighlighted form later.

    GitHub.cache.set(styling_directives_cache_key_short_code, result, 0, false)
    result
  end

  def colorized_lines_cache_key
    cache_key_parts = [
      CacheKeyLoggingDenylist::TREE_ENTRY_PREFIX,
      "v22",

      # Changes to our syntax highlighting code affect the syntax-highlighted
      # output.
      GitHub::Colorize.cache_key_prefix,

      # The blob's contents affect its colorized contents (duh).
      oid,

      # Ideally we'd include the actual TextMate scope in the cache key, as
      # that is what directly determines the style of highlighting used. But
      # determining the scope for a blob requires loading that blob's data,
      # which is expensive, to see if the blob is binary. Linguist uses three
      # things to determine a blob's language: its contents, its name, and its
      # mode. The contents is already represented by the OID above, so all
      # that's left is the name and mode.
      name,
      mode,

      # If the blob is truncated at a certain limit, we don't want to cache it for
      # any sizes other than that specific limit.
      truncated? ? "truncated-#{loc}" : "",
    ]

    # Does this TreeEntry represent a Gist snippet?
    # See packages/gists/app/view_models/gists/snippet_view.rb for more context.
    if snippet?
      cache_key_parts << "snippet"
    end

    cache_key_parts.join(":")
  end

  def styling_directives_cache_key_short_code
    colorized_lines_cache_key + ":styling_directives:v2"
  end

  def snippet?
    @snippet
  end

  def async_workflow
    async_repository.then(&:async_workflows).then do |workflows|
      workflows.find { |w| w.path == path }
    end
  end

  # Public: Determine if we should try to render the blob via the
  # GitHub::Markup gem. We won't render the blob if it is binary or if it is
  # too big. We cannot rely on the GitHub::Markup.can_render? method because
  # it does not allow us to override the language of the file and GitHub supports
  # overriding linguist via .gitattributes.
  #
  # Returns true if we can safely render the blob.
  def can_render?
    lang = self.language
    lang ||= GitHub::Markup.language(self.name, self.data, symlink: !!self.symlink_source)

    GitHub::Markup.markup_impls.any? do |impl|
      impl.match?(self.name, lang)
    end
  end

  private

  # Transcode blob data to UTF-8. This may mutate the input in some cases.
  def transcode(blob_data)
    return if blob_data.nil?

    if linguist_encoding = attributes["linguist-encoding"]
      return GitHub::Encoding.transcode(blob_data, linguist_encoding, GitHub::Encoding::UTF8)
    elsif info["binary"]
      return blob_data
    end

    if blob_data.encoding == ::Encoding::UTF_8
      blob_data.scrub!
    elsif blob_data.bytesize < GitHub::Encoding::DETECTABLE_LENGTH
      # The blob is small enough that we don't trust the detected encoding.
      # Just assume it's UTF-8.
      blob_data.force_encoding(::Encoding::UTF_8).scrub!
    else
      GitHub::Encoding.transcode(blob_data, info["encoding"], GitHub::Encoding::UTF8)
    end
  end
end
