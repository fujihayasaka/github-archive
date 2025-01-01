# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    module Selectors
      class ByRef < SelectorObject

        # Returns the path object selector to resolve the path object.
        sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def path_object_selector
          return unless path.present?

          { by_treeish_and_path: { treeish: { reference: { name: qualified_ref_name.b } }, path: { name: T.must(path).b } } }
        end

      end
    end
  end
end
