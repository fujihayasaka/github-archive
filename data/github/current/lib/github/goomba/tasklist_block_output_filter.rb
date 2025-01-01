# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class TasklistBlockOutputFilter < AsyncOutputFilter
    sig { returns(T::Array[Symbol]) }
    def self.feature_flags
      [:tasklist_block_nested_html_pipeline, :tasklist_block_precache]
    end

    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
    def self.cache_key(context)
      Async::TasklistBlockFilter.cache_key(context)
    end

    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.enabled?(context)
      Async::TasklistBlockFilter.enabled?(context)
    end

    sig { params(html: String).returns(Promise[T.untyped]) }
    def async_call(html)
      doc = Goomba::DocumentFragment.new(html, nil)
      filter = Async::TasklistBlockFilter.new(context, result, scratch)

      filter.async_scan_doc(doc).then do
        result = doc.to_html(filters: [filter])
        filter.finished
        result
      end
    end
  end
end
