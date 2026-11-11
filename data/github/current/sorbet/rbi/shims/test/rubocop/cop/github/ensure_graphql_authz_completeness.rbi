# typed: true

module RuboCop
  module Cop
    module GitHub
      class EnsureGraphQLAuthzCompleteness < Base
        def assert_graphql_authz?(node); end

        def starts_with_block?(node); end
      end
    end
  end
end
