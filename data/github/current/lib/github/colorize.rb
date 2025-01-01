# typed: true
# frozen_string_literal: true

require "active_support/core_ext/string"

module GitHub
  module Colorize
    DEFAULT_TIMEOUT = 5
    SNIPPET_HEADERS = { "text.html.php" => "<?php\n" }

    include GitHub::Encoding
    include GitHub::Timer
    extend self

    class InProcessHighlighterCalled < StandardError; end
    class RPCError < StandardError; end

    # String that should be used as part of the cache key when caching
    # syntax highlighting results.
    def cache_key_prefix
      "#{GitHub::Treelights.cache_key}/v2"
    end

    # String that should be used as part of stats reported about syntax
    # highlighting.
    def stats_key
      "treelights"
    end

    # Check if syntax highlighting is supported for the given scope string
    def valid_scope?(scope)
      GitHub::Treelights.valid_scopes.include?(scope)
    end

    # Syntax-highlights one document.
    #
    # Arguments:
    #   scope - TM scope string
    #   text - Code to highlight
    #   timeout - Timeout in seconds
    #   code_snippet - Is this a code snippet within a markdown document
    #   fallback_to_plain - Handle any error by treating the document as plain text.
    #
    # Returns an Array of syntax-highlighted lines. Returns `nil` if
    # `fallback_to_plain` is set to `false` and the code could not be highlighted,
    # either due to a timeout or an invalid scope.
    #
    # Raises a `GitHub::Colorize::RPCError` if `fallback_to_plain` is set to
    # `false` and there's a failure to connect to the syntax highlighting service.
    #
    # If `fallback_to_plain` is set to `true`, no error will ever be thrown.
    def highlight_one(scope, text, timeout: DEFAULT_TIMEOUT, code_snippet: false, fallback_to_plain: true)
      if !scope || scope == "none"
        return fallback_to_plain ? highlight_plain(text) : nil
      end

      GitHub.tracer.in_span("GitHub::Colorize.highlight_one",
                            attributes: {
                              "gh.colorize.scope" => scope,
                              "gh.colorize.timeout" => timeout,
                              "gh.colorize.code_snippet" => code_snippet,
                              "gh.colorize.fallback_to_plain" => fallback_to_plain,
                            }, kind: :internal) do |span|
        span.add_event("text_length", attributes: { "gh.colorize.text_length" => text.length })

        if !valid_scope?(scope)
          span.add_event("invalid scope #{scope.inspect}")
        else
          span.add_event("guessing encoding")
          text = guess_encoding_and_transcode(text)

          # When highlighting code snippets, prepend an implicit header line if
          # one is needed for the given language.
          if code_snippet
            header = SNIPPET_HEADERS[scope]
            if header && !text.start_with?(header)
              text = header + text
            else
              header = nil
            end
          end

          lines = GitHub.dogstats.time("colorize", tags: ["backend:#{stats_key}", "snippet:#{code_snippet}"]) do
            GitHub.tracer.in_span("GitHub::Colorize.highlight_one", attributes: {
              "gh.colorize.backend" => stats_key,
              "gh.colorize.code_snippet" => code_snippet
            }, kind: :internal) do |_span|
              GitHub::Treelights.highlight(scope, text, timeout: timeout)
            end

          # If an RPC call fails, raise an RPCError so that callers can
          # distinguish this from an ordinary failure to highlight.
          rescue GitHub::Treelights::RPCError
            raise RPCError unless fallback_to_plain
          end
        end

        # If anything went wrong and fallback_to_plain was passed, then fall back
        # to returning an array of unhighlighted, HTML-safe lines.
        if !lines && fallback_to_plain
          span.add_event("falling back to plain")
          lines = highlight_plain(text)
        end

        # If a header was prepended, remove it from the output.
        header ? lines[1..-1] : lines
      end
    end

    # Converts a string of code into a string of HTML-escaped lines,
    # similar to what would be produced by syntax highlighting. This
    # can be used as a fallback if syntax highlighting fails.
    #
    # Arguments:
    # * `data` - A string of code
    #
    # Returns an Array of HTML-safe strings.
    def highlight_plain(data)
      GitHub.tracer.in_span("GitHub::Colorize.highlight_plain", kind: :internal) do |span|
        span.add_event("data", attributes: { "gh.colorize.data_length" => data.length })
        lines = ERB::Util.force_escape(data).split("\n", -1).map(&:html_safe)
        lines.pop if !lines.empty? && lines.last.empty?
        lines
      end
    end

    # Syntax-highlights many documents at once.
    #
    # Arguments are of the form:
    #
    #   scopes - Array of TM scope values
    #   texts - Array of strings containing code to highlight
    #   timeout — Timeout in seconds
    #   code_snippet - Are these code snippets within a markdown document
    #
    # Returns an Array of Arrays of syntax-highlighted lines, one element for
    # each scope/text pair passed to this function. Any documents that cannot
    # be highlighted are represented by nil in the returned Array.
    #
    # Never raises errors. If the syntax highlighting service is unavailable,
    # returns an empty array (as if each individual document had failed to
    # highlight).
    def highlight_many(input_scopes, input_texts, code_snippet: false, timeout: DEFAULT_TIMEOUT)
      # Build up arrays of scopes and texts to highlight. Do not include
      # entries with invalid scopes. At the same time, maintain an array
      # containing the new index for each input index.
      valid_indices = []
      valid_scopes = []
      valid_texts = []
      header_flags = []
      input_texts.each.with_index do |text, i|
        scope = input_scopes[i]
        if valid_scope?(scope)
          text = guess_encoding_and_transcode(text)

          # When highlighting code snippets, some languages need a line of
          # context to be added, to ensure useful highlighting. Keep track
          # of which entries have had such a line prepended, so that it can
          # be removed from the output.
          if code_snippet
            header = SNIPPET_HEADERS[scope]
            if header && !text.start_with?(header)
              text = header + text
              header_flags << true
            else
              header_flags << false
            end
          end

          valid_indices << valid_texts.length
          valid_scopes << scope
          valid_texts << text
        else
          valid_indices << nil
        end
      end

      return [] if valid_scopes.length == 0

      GitHub.tracer.in_span("GitHub::Colorize.highlight_many", attributes: { "gh.colorize.timeout" => timeout }, kind: :internal) do |span|
        span.add_event("scopes", attributes: { "gh.colorize.scope_length" => valid_scopes.length, "gh.colorize.text_length" => valid_texts.length })

        docs = GitHub.dogstats.time("colorize_many", tags: ["backend:#{stats_key}"]) do
          GitHub.tracer.in_span("GitHub::Colorize.colorize_many", attributes: { "gh.colorize.backend" => stats_key }, kind: :internal) do |_span|
            GitHub::Treelights.highlight_many(valid_scopes, valid_texts, timeout: timeout)
          end
        end

        if docs.any?(&:nil?)
          GitHub.dogstats.increment("colorize_many", tags: ["action:colorize_many", "backend:#{stats_key}", "error:timeout"])
        end

        valid_indices.map do |index|
          if index
            lines = docs[index]

            # If a header line was prepended, remove it from the highlighted output.
            if lines && header_flags[index]
              lines.shift
            end
            lines
          end
        end
      rescue GitHub::Treelights::RPCError => error
        span.record_exception(error)
        []
      end
    end

    # Gets a list of syntax-highligted tokens for one document.
    #
    # Arguments:
    #   scope - TM scope string
    #   text - Code to highlight
    #   timeout - Timeout in seconds
    #   fallback_to_plain - Handle any error by treating the document as plain text.
    #
    # Returns an Array of Arrays of tokens. Returns `nil` if
    # `fallback_to_plain` is set to `false` and the code could not be highlighted,
    # either due to a timeout or an invalid scope.
    #
    # Raises a `GitHub::Colorize::RPCError` if `fallback_to_plain` is set to
    # `false` and there's a failure to connect to the syntax highlighting service.
    #
    # If `fallback_to_plain` is set to `true`, no error will ever be thrown.
    def styling_directives(scope, text, timeout: DEFAULT_TIMEOUT, fallback_to_plain: false)
      if !scope || scope == "none"
        return nil
      end

      GitHub.tracer.in_span("GitHub::Colorize.styling_directives",
                            attributes: {
                              "gh.colorize.scope" => scope,
                              "gh.colorize.timeout" => timeout,
                              "gh.colorize.fallback_to_plain" => fallback_to_plain,
                            }, kind: :internal) do |span|
        span.add_event("text_length", attributes: { "gh.colorize.text_length" => text.length })

        if !valid_scope?(scope)
          span.add_event("invalid scope #{scope.inspect}")
        else
          span.add_event("guessing encoding")
          text = guess_encoding_and_transcode(text)

          directives = GitHub.dogstats.time("styling_directives", tags: ["backend:#{stats_key}"]) do
            GitHub.tracer.in_span("GitHub::Colorize.styling_directives", attributes: {
              "gh.colorize.backend" => stats_key
            }, kind: :internal) do |_span|
              GitHub::Treelights.styling_directives(scope, text, timeout: timeout)
            end

          # If an RPC call fails, raise an RPCError so that callers can
          # distinguish this from an ordinary failure to highlight.
          rescue GitHub::Treelights::RPCError
            raise RPCError unless fallback_to_plain
          end
        end

        # If anything went wrong and fallback_to_plain was passed, then fall back
        # to returning en empty array of styling directives for each line (no tokens to highlight)
        if !directives && fallback_to_plain
          span.add_event("falling back to plain")
          directives = styling_directives_plain(text)
        end

        directives
      end
    end

    # Converts a string of code into a list of empty lists of styling directives,
    # equivalent to what would be produced for a file that requires no highlighting.
    # This can be used as a fallback if syntax highlighting fails.
    #
    # Arguments:
    # * `data` - A string of code
    #
    # Returns an Array of empty arrays.
    def styling_directives_plain(data)
      GitHub.tracer.in_span("GitHub::Colorize.styling_directives_plain", kind: :internal) do |span|
        span.add_event("data", attributes: { "gh.colorize.data_length" => data.length })
        lines = ERB::Util.force_escape(data).split("\n", -1).map(&:html_safe)

        directives = lines.length.times.collect { [] }
        directives.pop if !lines.empty? && lines.last.empty?

        directives
      end
    end

    # Helper: Syntax-highlights a string as JSON
    # and returns it as a full html chunk, including the
    # wrapping classes.
    def highlight_json(text)
      if lines = highlight_one("source.json", text)
        (%q{<div class="highlight"><pre>} + lines.join("\n") + %q{</pre></div>}).html_safe # rubocop:disable Rails/OutputSafety
      end
    end
  end
end
