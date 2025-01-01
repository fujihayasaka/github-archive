# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Swp
      module Page
        # Collection of methods to help traverse the Contentful response.
        module Traversal
          extend T::Helpers

          include GitHub::Memoizer

          abstract!

          requires_ancestor { Site::Contentful::Page }

          delegate \
            :contentful_response,
            :get_field,
            :fields,
            :find_link,
            :items,
            :includes,
            :included_entries,
            to: :traverser

          private

          sig { returns(Traverser) }
          memoize def traverser
            Traverser.new(view_data)
          end
        end
      end
    end
  end
end
