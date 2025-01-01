# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class TrackingBlockOutputFilter < AsyncOutputFilter
    def self.feature_flags
      [:tasklist_block, :tasklist_block_nested_html_pipeline, :tasklist_block_precache]
    end

    def self.cache_key(context)
      Async::TrackingBlockFilter.cache_key(context)
    end

    def self.enabled?(context)
      Async::TrackingBlockFilter.enabled?(context)
    end

    def async_call(html)
      doc = Goomba::DocumentFragment.new(html, nil)
      filter = Async::TrackingBlockFilter.new(context, result, scratch)
      filter.async_scan_doc(doc).then do
        result = doc.to_html(filters: [filter])
        filter.finished
        result
      end
    end
  end
end
