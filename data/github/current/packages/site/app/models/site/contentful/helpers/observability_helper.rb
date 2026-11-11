# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Helpers
      module ObservabilityHelper
        extend T::Helpers
        include Kernel

        abstract!

        sig { abstract.returns(Page::CacheKey) }
        def cache_key; end

        sig { returns(T::Array[String]) }
        def metric_tags
          ["page_class:#{self.class.name}"]
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def log_context
          { "code.namespace": self.class.name, **cache_key.to_log }
        end
      end
    end
  end
end
