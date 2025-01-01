# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class SnippetClipboardCopyFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper

    GH_SELECTOR = "gh:snippet-clipboard-copy-content"
    SELECTOR = Goomba::Selector.new("[gh|snippet-clipboard-copy-content]")

    DIV_SELECTOR = Goomba::Selector.new(match: "div")
    PRE_SELECTOR = Goomba::Selector.new(match: "pre")

    def initialize(*args)
      super
    end

    def selector
      SELECTOR
    end

    def async_scan
      Promise.all(@nodes)
    end

    def call(node)
      content = node[GH_SELECTOR].to_s
      content.chop! if content[-1] == "\n"
      node.remove_attribute(GH_SELECTOR)

      if node =~ DIV_SELECTOR
        call_div(node, content)
      elsif node =~ PRE_SELECTOR
        call_pre(node, content)
      end
    end

    private

    def add_class(element, klass)
      element["class"] = Array(element["class"]).concat([klass]).uniq.join(" ")
    end

    def call_div(node, content)
      add_notranslate_class(node)

      add_class(node, "position-relative")
      add_class(node, "overflow-auto")

      lang = node["gh:snippet-language"] || node["lang"]

      unless context[:use_primer_clipboard_copy]
        node["data-snippet-clipboard-copy-content"] = content
        return node.to_html
      end

      enhance_with_primer_clipboard_copy(node, lang, content)
    end

    def call_pre(node, content)
      add_notranslate_class(node)

      fragment = Goomba::DocumentFragment.new(
        %Q{<div class="snippet-clipboard-content">#{node.to_html}</div>}
      )

      call_div(fragment.children.first, content)
    end

    # Because this filter runs asynchronously, it bypasses NoTranslationFilter, hence we have to apply the `notranslate` class manually
    def add_notranslate_class(node)
      add_class(node, "notranslate")
    end

    sig { params(node: ::Goomba::ElementNode, lang: T.nilable(String), content: String).returns(String) }
    def enhance_with_primer_clipboard_copy(node, lang, content)
      inner = ApplicationController.render(
        partial: "filter_partials/snippet_clipboard_copy",
        formats: [:html],
        layout: false,
        locals: {
          content:,
          snippet: safe_html_if_sanitized(node.inner_html),
          snippet_language: lang ? Linguist::Language[lang] : nil,
        }
      )

      ActionController::Base.helpers.content_tag(
        node.tag.to_sym,
        inner,
        **node.attributes,
      )
    end
  end
end
