# typed: true

module RuboCop
  module Cop
    module GitHub
      class RemoveAuthMatricesInAssertAuthzCoveredByTestFramework < Base
        def asserted_actors(node); end

        def authz_assertions(node, &blk); end

        def authz_test?(node); end

        def class_instantiation?(node); end

        def direct_variable_interpolation?(node); end

        def fixtures_block?(node); end

        def interpolate_value?(node); end

        def ivar_string_assigns(node); end

        def lvar_string_assigns(node); end

        def matrix_actor(node); end

        def referenced_variable_name(node); end

        def repo_nwo?(node); end

        def some_weird_send?(node); end

        def string_addition?(node); end

        def path_nodes(node); end
      end
    end
  end
end
