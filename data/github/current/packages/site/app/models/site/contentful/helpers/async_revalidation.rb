# typed: strict
# frozen_string_literal: true

require_relative "../../k_v"

module Site
  module Contentful
    module Helpers
      module AsyncRevalidation
        extend T::Helpers
        requires_ancestor { Site::Contentful::Page }

        abstract!

        sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
        def serialize; end

        sig { abstract.returns(T::Boolean) }
        def preview?; end

        sig { void }
        def async_revalidate
          return if preview?
          RevalidatePageJob.perform_later(self.class, serialize)
        end
      end
    end
  end
end
