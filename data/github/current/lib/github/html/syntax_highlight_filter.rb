# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class SyntaxHighlightFilter < Filter

    def self.cache_key(context)
      # Changes to our syntax highlighting code affect the rendering of fenced
      # code blocks.
      GitHub::Colorize.cache_key_prefix
    end

    def call
      doc.search("pre").each do |node|
        html = syntax_highlight_filter(node)
        next if html.nil?
        node.replace(html)
      end
      doc
    end

    def syntax_highlight_filter(node, lang = nil)
      default = context[:highlight] && context[:highlight].to_s
      return unless lang = node["lang"] || default
      return unless scope = tm_scope_for(lang)

      # FIXME: Remove the respond_to? and always use node.text_content once we
      # fully transition to Goomba.
      text = node.respond_to?(:text_content) ? node.text_content : node.inner_text
      lines = GitHub::Colorize.highlight_one(scope, text, timeout: 1, code_snippet: true, fallback_to_plain: false)
      return unless lines

      scope = scope.gsub(".", "-")

      # This adds the <clipboard-copy> button as a sibling node in the filter now
      # instead of afterwards in an async call. This is simply because
      # HTML::Pipeline doesn't support Async filters.
      if wiki_clipboard_copy_enabled?
        content = EscapeHelper.safe_join(lines, "\n")
        clipboard_filter_selector = ::GitHub::Goomba::Async::SnippetClipboardCopyFilter::GH_SELECTOR
        options = { :class => "highlight highlight-#{scope}", clipboard_filter_selector => text }

        html = ActionController::Base.helpers.content_tag(:div, options) do
          ActionController::Base.helpers.content_tag(:pre, content)
        end

        return ::GitHub::Goomba::Async::SnippetClipboardCopyFilter.to_html(html, context)
      end

      content = lines.join("\n")
      %Q{<div class="highlight highlight-#{scope}"><pre>#{content}</pre></div>}
    rescue GitHub::Colorize::RPCError
      nil
    end

    def language_for(lang_name)
      # FIXME: We can probably come up with a better way to choose between
      # multiple languages that handle a single file extension. Perhaps we
      # could pass the text to be highlighted to Linguist and have it classify
      # it for us. For now we'll just choose the first language that supports
      # the file extension.
      with_period = lang_name.gsub(%r{\A\.?}, ".")
      Linguist::Language[lang_name] || Linguist::Language.find_by_extension(with_period).first
    end

    def tm_scope_for(lang_name)
      if lang = language_for(lang_name)
        lang.tm_scope
      end
    end

    def wiki_clipboard_copy_enabled?
      return @clipboard_copy_enabled if defined?(@clipboard_copy_enabled)
      @clipboard_copy_enabled = wiki_context
    end

    def wiki_context
      return false unless context[:page] && context[:page].is_a?(::GitHub::Unsullied::Page)

      repository = context[:page].wiki&.repository
      return false unless repository

      true
    end
  end
end
