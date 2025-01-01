module RuboCop
  module Cop
    module GitHub
      class RequireSymbolPermissionActions < Base
        def matrix_instantiation?(node); end

        def permissions_hash(node); end

        def permission_name_and_action(node); end

        def symbol_action?(node); end
      end
    end
  end
end
