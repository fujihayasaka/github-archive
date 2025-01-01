# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class IssueBlobFilter < NodeFilter
    MAX_SNIPPET_LINE_INDEX = 11
    SELECTOR = Goomba::Selector.new(match: "gh|blob-mention")
    TIMEOUT = 1 # second

    def initialize(*args)
      super
      @blob_cache = {}
      @key_to_blob_oids = {}
      @timeout_counter = GitHub::TimeoutCounter.new(TIMEOUT)
    end

    def selector
      SELECTOR
    end

    def self.enabled?(context)
      context[:entity].is_a?(Repository)
    end

    def async_scan
      return unless repository

      result[:issue_blob_references] = []

      Promise.all(@nodes.map do |node|
        Platform::Loaders::TreeEntry.load(repository, node["commit_oid"], Addressable::URI.unescape(node["filepath"]).b).then do |blob|
          next unless blob

          async_colorized_lines = Platform::Loaders::Cache.load(blob.colorized_lines_cache_key).then do |cached_colorized_lines|
            next cached_colorized_lines if cached_colorized_lines

            Platform::Loaders::TreeEntryColorizedLines.load(blob, timeout_counter: @timeout_counter).then do |colorized_lines|
              if colorized_lines
                # Write to the cache, but only if we have a colorization result
                blob.set_colorized_lines(colorized_lines)
                colorized_lines
              else
                lines = force_escape_with_transcoding_guess(blob.info["data"]).split("\n", -1)
                lines.pop if !lines.empty? && lines.last.empty?
                lines.map(&:html_safe)
              end
            end
          end

          async_colorized_lines.then do |colorized_lines|
            @key_to_blob_oids[[node["commit_oid"], node["filepath"]]] = blob.info["oid"]
            @blob_cache[[node["commit_oid"], node["filepath"]]] = colorized_lines
          end
        end
      end)
    end

    # Translates a `<gh:blob-mention>` tag into regular HTML.
    def call(node)
      filepath = node["filepath"] # URI encoded.
      commit_oid = node["commit_oid"]
      range_start = node["range_start"].to_i
      range_end = node["range_end"].to_i
      permalink = node["permalink"] # URI encoded, for correct roundtrips.
      inner_html = node["text"]

      blob_lines = @blob_cache[[node["commit_oid"], node["filepath"]]]

      if blob_lines && is_range_valid?(range_start, range_end, blob_lines)
        decoded_filepath = Addressable::URI.unescape(filepath).b
        blob_oid = @key_to_blob_oids[[node["commit_oid"], node["filepath"]]]

        result[:issue_blob_references] << {
          filepath: decoded_filepath,
          commit_oid: commit_oid,
          range_start: range_start,
          range_end: range_end,
          blob_oid: blob_oid,
        }

        generate_html(permalink, decoded_filepath, commit_oid, range_start, range_end, blob_lines)
      else # Invalid filepath, commit id and/or range -> return link
        ActionController::Base.helpers.link_to safe_html_if_sanitized(inner_html), permalink
      end
    end

    def is_range_valid?(range_start, range_end, blob_lines)
      range_start > 0 && range_start <= range_end && range_end <= blob_lines.length
    end

    def generate_html(permalink, filepath, commit_oid, range_start, range_end, lines)
      repo_name = repository.name
      repo_name_with_filepath = "#{repo_name}/#{filepath.dup.force_encoding("utf-8").scrub!}"

      owner_display_login = repository.owner.display_login

      lines = lines[(range_start - 1)..(range_end - 1)]
      lines = strip_leading_whitespace(lines)

      locals = {
        owner_display_login: owner_display_login,
        permalink: permalink,
        filepath: repo_name_with_filepath,
        commit_oid: commit_oid,
        range_start: range_start,
        range_end: range_end,
        lines: lines,
        repo_name: repo_name,
      }

      ApplicationController.render(partial: "filter_partials/issue_blob_reference", locals: locals, formats: [:html])
    end

    # lines - an array of strings, usually representing a blob reference
    # finds minimum amount of leading whitespace on a single non-empty lines
    # and strips that amount from all lines.
    def strip_leading_whitespace(lines)
      return if lines.empty?

      min_whitespace = lines.map(&:length).max

      lines.each do |line|
        if line =~ /\A([ \t]*)(?=\S)/
          min_whitespace = [$1.length, min_whitespace].min
        end
      end

      lines.map do |line|
        new_line = line.sub(/\A[ \t]{#{min_whitespace}}/, "")
        if line.html_safe?
          new_line.html_safe # rubocop:disable Rails/OutputSafety
        else
          new_line
        end
      end
    end
  end
end
