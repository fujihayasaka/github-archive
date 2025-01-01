# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class SyntaxHighlightFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("pre")

    def self.cache_key(context)
      # Changes to our syntax highlighting code affect the syntax-highlighted
      # output.
      GitHub::Colorize.cache_key_prefix
    end

    def initialize(*args)
      super
      @results_by_node = {}
      @default_lang = context[:highlight]&.to_s
      @filter = GitHub::HTML::SyntaxHighlightFilter.new("", context, result)
      @snippet_clipboard_copy_filter_enabled = SnippetClipboardCopyFilter.enabled?(context)
    end

    def selector
      SELECTOR
    end

    # Find all of the code blocks that should be syntax highlighted and
    # highlight them all in parallel using one highlighting request.
    # This avoids the performance cost of making one highlighting request
    # for each code block.
    def scan(document)
      nodes = []
      scopes = []
      strings = []

      document.select(SELECTOR).each do |node|
        if lang = node["lang"] || @default_lang
          if scope = @filter.tm_scope_for(lang)
            content = node.text_content
            scopes.push(scope)
            strings.push(content)
            nodes.push(node)
          end
        end
      end

      results = GitHub::Colorize.highlight_many(scopes, strings, code_snippet: true, timeout: 3)
      results.each_with_index do |lines, i|
        if lines
          node = nodes[i]
          scope = scopes[i].gsub(".", "-")

          @results_by_node[node.to_html] = if gh_clipboard_copy_enabled?
            content = EscapeHelper.safe_join(lines, "\n")

            ActionController::Base.helpers.content_tag(:div, :class => "highlight highlight-#{scope}", clipboard_filter_selector => node.text_content) do
              ActionController::Base.helpers.content_tag(:pre, content)
            end
          else
            content = lines.join("\n")
            %Q{<div class="highlight highlight-#{scope}"><pre>#{content}</pre></div>}
          end
        end
      end
    rescue GitHub::Colorize::RPCError
      nil
    end

    # Retrieve the precomputed syntax highlighted version of this code block.
    def call(node)
      @results_by_node[node.to_html]
    end

    private

    def clipboard_filter_selector
      ::GitHub::Goomba::Async::SnippetClipboardCopyFilter::GH_SELECTOR
    end

    def gh_clipboard_copy_enabled?
      !!@snippet_clipboard_copy_filter_enabled
    end
  end
end
