# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Swp
      module Page
        module Seo
          extend T::Helpers

          requires_ancestor { Site::Contentful::Swp::Page::Traversal }

          sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
          def seo
            (get_field("seo") || {}).fetch("fields", {})
          end
        end
      end
    end
  end
end
