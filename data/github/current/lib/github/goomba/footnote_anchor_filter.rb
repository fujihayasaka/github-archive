# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Node filter that
  # - rewrites the href value for footnotes so that :target styles can apply
  # - adds aria attributes
  # - appends a pipeline_run_id to the footnote-ref node's id to ensure refs
  # are unique within the document
  class FootnoteAnchorFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "a[data-footnote-ref],a[data-footnote-backref]")

    def self.cache_key(context)
      [
        context[:pipeline_run_id],
        context[:name_prefix]
      ].reject(&:blank?).join(":")
    end

    def call(node)
      # The href may be nil if the footnote identifier contains invalid characters.
      if node["href"]
        href = node["href"].sub("#", "##{prefix}")
        href = href.concat("-", pipeline_run_id) if pipeline_run_id
        node["href"] = href
      end

      if node["data-footnote-ref"]
        node["id"] = node["id"].concat("-", pipeline_run_id) if node["id"] && pipeline_run_id

        node["aria-describedby"] = "footnote-label"
      end

      if node["data-footnote-backref"]
        node["class"] = "data-footnote-backref"
      end

      node
    end

    def selector
      SELECTOR
    end

    private

    def pipeline_run_id
      context[:pipeline_run_id]
    end

    def prefix
      context[:name_prefix]
    end
  end
end
