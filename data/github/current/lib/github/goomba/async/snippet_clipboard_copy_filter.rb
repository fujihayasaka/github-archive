# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class SnippetClipboardCopyFilter < NodeFilter
    GH_SELECTOR = "gh:snippet-clipboard-copy-content"
    SELECTOR = Goomba::Selector.new("[gh|snippet-clipboard-copy-content]")

    DIV_SELECTOR = Goomba::Selector.new(match: "div")
    PRE_SELECTOR = Goomba::Selector.new(
      match: "pre",
      reject: "pre[lang='[tasklist]']"
    )

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
      node["data-snippet-clipboard-copy-content"] = content

      node.to_html
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
  end
end
