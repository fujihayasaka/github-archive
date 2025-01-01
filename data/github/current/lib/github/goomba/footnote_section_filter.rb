# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Node filter that
  # - inserts an h2 title into the section for screen readers
  # - makes the footnote list item targets within a footnotes
  # section unique by appending a pipeline_run_id generated
  # at render time
  class FootnoteSectionFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "section[data-footnotes]")

    def self.cache_key(context)
      context[:pipeline_run_id]
    end

    def call(node)
      node.select("li") do |li|
        if pipeline_run_id && li["id"]
          li["id"] = li["id"].concat("-", pipeline_run_id)
        end
        li
      end

      node["class"] = "footnotes"
      inner_html = tag.h2("Footnotes", id: "footnote-label", class: "sr-only") + safe_html_if_sanitized(node.inner_html)

      # We return a DocumentFragment here because we want to continue running filters on the children. Once
      # Goomba's updated to recurse filters on individual returned elements, we can remove this fragment wrapper
      Goomba::DocumentFragment.new(tag.section(inner_html, **node.attributes))
    end

    def selector
      SELECTOR
    end

    private

    def tag
      @tag ||= ActionController::Base.helpers.tag
    end

    def pipeline_run_id
      context[:pipeline_run_id]
    end
  end
end
