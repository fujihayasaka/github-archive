# typed: true
# frozen_string_literal: true

require "cache_key_logging_denylist"

class SyntaxHighlightedDiff
  # Each highlighted entry requires loading two blobs, each of which consumes
  # memory and CPU to process. This is the maximum number of entries we'll try
  # to highlight to avoid consuming too many resources.
  MAXIMUM_HIGHLIGHTED_ENTRIES = 50

  # This value is stored in GitHub.cache for GitHub::Diff::Entrys that can't be
  # highlighted. This prevents us from trying to highlight them again on
  # subsequent calls to #highlight!.
  UNHIGHLIGHTABLE = :unhighlightable

  include EscapeHelper

  # Initialize a new SyntaxHighlightedDiff
  #
  # repository   - The Repository to fetch blobs from.
  # stats_prefix - The String stats key namespace to store stats under.
  def initialize(repository, stats_prefix: "diff.prepare_for_syntax_highlighting_diffs")
    @repository = repository
    @stats_prefix = stats_prefix
  end

  def frozen_colorized_lines(entry)
    _, result = frozen_colorized_lines_with_cache_code(entry)
    result
  end

  def frozen_colorized_lines_with_cache_code(entry)
    cache_code, lines = colorized_lines_with_cache_code(entry)
    [cache_code, lines&.each(&:freeze).freeze]
  end

  # Retrieves a GitHub::Diff::Entry's syntax-highlighted diff text. The entry
  # must previously have been highlighted via #highlight!.
  #
  # entry - The GitHub::Diff::Entry to highlight.
  #
  # Returns an Array of HTML strings for each line position. Array entries maybe
  # nil if the line was a nonewline marker. If the highlighted text could not be
  # found, nil will be returned instead of an Array.
  def colorized_lines(entry)
    _, result = colorized_lines_with_cache_code(entry)
    result
  end

  def colorized_lines_with_cache_code(entry)
    return nil if entry.nil? || entry.submodule? || entry.text.blank?

    start = GitHub::Dogstats.monotonic_time

    key = colorized_lines_cache_key(entry)
    result = GitHub.cache.get(key)
    GitHub.dogstats.timing_since("syntax_highlighted_diff.colorized_lines.cache.#{result.nil? ? "miss" : "hit"}", start)

    cache_code = if result.nil?
      :miss
    elsif result == UNHIGHLIGHTABLE
      UNHIGHLIGHTABLE
    else
      :hit
    end
    [cache_code, cache_code == :hit ? result : nil]
  end

  # Highlight as many of the diff entries as possible in bounded time.
  #
  # Syntax-highlighting data is pulled in-process from memcached, and
  # syntax-highlighting is performed for blobs that aren't already in the
  # cache.
  #
  # Large diffs can require lots of time spent highlighting, so we just
  # highlight as many blobs as we can within the timeout.
  #
  # entries - An Enumerable of GitHub::Diff::Entry objects.
  # attributes_commit_oid - Commit OID to use to load Git attributes
  # timeout - An Integer number of seconds to spend highlighting. Default: 1.
  #
  # Returns nothing.
  def highlight!(entries, attributes_commit_oid: nil, timeout: 1)
    return if entries.empty?

    GitHub.dogstats.time(@stats_prefix) do
      GitHub.dogstats.histogram("#{@stats_prefix}.total_entries", entries.count)

      to_highlight = entries_to_highlight(entries)

      loaded_blobs = load_blobs(to_highlight)
      TreeEntry.load_line_counts!(@repository, loaded_blobs)

      if loaded_blobs.any? && attributes_commit_oid
        begin
          TreeEntry.load_attributes!(loaded_blobs, attributes_commit_oid)
        rescue GitRPC::ObjectMissing => e
          # possible this data was from a PR that has had their refs removed so ignore missing data.
        end
      end

      blobs_to_highlight = highlightable_blobs(loaded_blobs)
      GitHub.dogstats.histogram("#{@stats_prefix}.blobs_to_highlight", blobs_to_highlight.count)

      highlightable_entries = reject_unhighlightable_entries(to_highlight, loaded_blobs.map(&:colorized_lines_cache_key) - blobs_to_highlight.map(&:colorized_lines_cache_key))

      highlight_blobs(blobs_to_highlight, timeout)
      highlight_entries(highlightable_entries)
    end
  end

  private

  def entry_base_blob(entry)
    return nil unless entry.a_blob && entry.a_blob != GitHub::NULL_OID
    TreeEntry.new(@repository, {
      "oid" => entry.a_blob,
      "path" => entry.a_path,
      "mode" => entry.a_mode,
      "type" => "blob",
    })
  end

  def entry_head_blob(entry)
    return nil unless entry.b_blob && entry.b_blob != GitHub::NULL_OID
    TreeEntry.new(@repository, {
      "oid" => entry.b_blob,
      "path" => entry.b_path,
      "mode" => entry.b_mode,
      "type" => "blob",
    })
  end

  def colorized_lines_cache_key(entry)
    # FIXME: This should probably take GitHub::Diff#cache_prefix into account.
    # That would let us get rid of entry.whitespace_ignored? below, and would
    # ensure that syntax highlighted diffs get regenerated whenever the parameters
    # we pass to `git diff-tree` change. Fixing that would probably require giving
    # GitHub::Diff::Entry a way to return its cache key.
    [
      CacheKeyLoggingDenylist::SYNTAX_HIGHLIGHTED_DIFF_PREFIX,
      "colorized_lines",
      "v6",
      # The highlighted diff obviously depends on the highlighted contents of
      # each blob.
      entry_base_blob(entry).try(:colorized_lines_cache_key),
      entry_head_blob(entry).try(:colorized_lines_cache_key),

      # If we have injected context lines into the diff to support context
      # annotations, the contents of the entry are not a pure function of the
      # blobs being diffed. We include a digest of the entry's text to ensure
      # the cache key changes when we inject a different set of lines.
      Digest::SHA256.hexdigest(entry.text.to_s),

      # The set of changed lines will be different when changes in whitespace
      # are ignored.
      entry.whitespace_ignored?,
    ].compact.join(":")
  end

  def colorized_lines!(entry)
    if base_blob = entry_base_blob(entry)
      base_lines = base_blob.colorized_lines(strategy: :from_cache_only)
    end

    if head_blob = entry_head_blob(entry)
      head_lines = head_blob.colorized_lines(strategy: :from_cache_only)
    end

    return if base_lines.blank? && head_lines.blank?

    entry.enumerator.reduce([]) do |lines, line|
      prefix, content = case line.type
      when :deletion
        ["-", base_lines && base_lines[line.left - 1]]
      when :addition
        ["+", head_lines && head_lines[line.right - 1]]
      when :context, :injected_context
        [" ", head_lines && head_lines[line.right - 1]]
      end
      lines[line.position] = content ? safe_join([prefix, content]) : h(line.text)
      lines
    end
  end

  def entries_to_highlight(entries)
    # Submodules appear in diffs but have no accompanying blobs. Diffs for
    # blank entries (e.g., binary files, renames, truncated diffs, etc.)
    # aren't displayed.
    diffable_entries = entries.reject { |entry| entry.submodule? || entry.text.blank? }
    GitHub.dogstats.histogram("#{@stats_prefix}.diffable_entries", diffable_entries.count)

    uncached_entries = GitHub.dogstats.time(@stats_prefix, tags: ["action:entries_to_highlight.reject_cached_entries"]) do
      reject_cached_entries(diffable_entries)
    end
    GitHub.dogstats.histogram("#{@stats_prefix}.uncached_entries", uncached_entries.count)

    to_highlight = uncached_entries.take(MAXIMUM_HIGHLIGHTED_ENTRIES)
    GitHub.dogstats.histogram("#{@stats_prefix}.entries_to_highlight", to_highlight.count)
    to_highlight
  end

  def reject_cached_entries(entries)
    entries_by_cache_key = entries.each_with_object({}) do |entry, hash|
      hash[colorized_lines_cache_key(entry)] = entry
    end

    cache_keys = entries_by_cache_key.keys
    lines_by_cache_key = GitHub.dogstats.time(@stats_prefix, tags: ["action:reject_cached_entries.fetch_entries_from_cache"]) do
      GitHub.cache.get_multi(cache_keys)
    end

    # Figure out what entries still need to be highlighted.
    cacheless_keys = cache_keys - lines_by_cache_key.keys
    cacheless_keys.map { |key| entries_by_cache_key[key] }
  end

  # Loads the blobs needed for highlighting entries from Git. Blobs that are
  # already highlighted are not loaded.
  def load_blobs(entries)
    blobs_by_cache_key = entries.each_with_object({}) do |entry, hash|
      if base_blob = entry_base_blob(entry)
        hash[base_blob.colorized_lines_cache_key] = base_blob
      end
      if head_blob = entry_head_blob(entry)
        hash[head_blob.colorized_lines_cache_key] = head_blob
      end
    end

    GitHub.dogstats.histogram("#{@stats_prefix}.total_blobs", blobs_by_cache_key.count)

    return [] if blobs_by_cache_key.empty?

    cache_keys = blobs_by_cache_key.keys

    # Pull any already-highlighted blobs into the in-process cache.
    lines_by_cache_key = GitHub.dogstats.time(@stats_prefix, tags: ["action:load_blobs.fetch_from_cache"]) do
      GitHub.cache.get_multi(cache_keys)
    end

    # Figure out what blobs still need to be highlighted.
    cacheless_keys = cache_keys - lines_by_cache_key.keys
    uncached_blobs = cacheless_keys.map { |key| blobs_by_cache_key[key] }

    GitHub.dogstats.histogram("#{@stats_prefix}.uncached_blobs", uncached_blobs.count)

    # Fetch all the blobs from git at once.
    oids = uncached_blobs.map(&:oid)
    begin
      blob_infos = GitHub.dogstats.time(@stats_prefix, tags: ["action:load_blobs.rpc_read_blobs"]) do
        @repository.rpc.read_blobs(oids)
      end
    rescue GitRPC::ObjectMissing => e
      # Some blob doesn't actually exist in the repository. Surprising, but
      # not much we can do about it.
      GitHub.dogstats.increment(@stats_prefix, tags: ["error:object_missing"])
      Failbot.report!(e)
      return []
    end

    # Turn the blob infos into TreeEntry objects.
    GitHub.dogstats.time(@stats_prefix, tags: ["action:load_blobs.create_tree_entries"]) do
      blob_infos.zip(uncached_blobs).map do |info, original_blob|
        TreeEntry.new(@repository, info.reverse_merge(original_blob.info))
      end
    end
  end

  def highlightable_blobs(blobs)
    blobs_with_languages = blobs.select { |blob| blob.language && GitHub::Colorize.valid_scope?(blob.language.tm_scope) }
    GitHub.dogstats.histogram("#{@stats_prefix}.blobs_with_languages", blobs_with_languages.count)

    blobs_with_languages.select(&:safe_to_colorize?)
  end

  def reject_unhighlightable_entries(entries, unhighlightable_blob_cache_keys)
    return entries if unhighlightable_blob_cache_keys.empty?
    highlightable_entries, unhighlightable_entries = entries.partition do |entry|
      base_blob = entry_base_blob(entry)
      head_blob = entry_head_blob(entry)
      base_highlightable = base_blob && !unhighlightable_blob_cache_keys.include?(base_blob.colorized_lines_cache_key)
      head_highlightable = head_blob && !unhighlightable_blob_cache_keys.include?(head_blob.colorized_lines_cache_key)

      base_highlightable || head_highlightable
    end
    unhighlightable_entries.each do |entry|
      GitHub.cache.set(colorized_lines_cache_key(entry), UNHIGHLIGHTABLE)
    end
    highlightable_entries
  end

  def highlight_blobs(blobs, timeout)
    return if blobs.empty?

    unhighlighted_count = GitHub.dogstats.time(@stats_prefix, tags: ["action:highlight_blobs"]) do
      highlight_many(blobs, timeout)
    end
    GitHub.dogstats.histogram("#{@stats_prefix}.unhighlighted_blobs", unhighlighted_count)
  end

  def highlight_many(blobs, timeout)
    scopes = blobs.map { |blob| blob.language.tm_scope }
    contents = blobs.map { |blob| blob.data }
    results = GitHub::Colorize.highlight_many(scopes, contents, timeout: timeout)

    results.zip(blobs) do |result, blob|
      blob.set_colorized_lines(result) if result
    end

    results.count(nil)
  end

  def highlight_entries(entries)
    unhighlighted_entries = entries.reject { |entry| highlight_entry(entry) }
    GitHub.dogstats.histogram("#{@stats_prefix}.unhighlighted_entries", unhighlighted_entries.count)
    GitHub.dogstats.increment(@stats_prefix, tags: ["action:highlight_entries", "type:#{unhighlighted_entries.any? ? 'incomplete' : 'complete'}"])
  end

  def highlight_entry(entry)
    lines = colorized_lines!(entry)
    return if lines.nil?
    GitHub.cache.set(colorized_lines_cache_key(entry), lines)
    lines
  end
end
