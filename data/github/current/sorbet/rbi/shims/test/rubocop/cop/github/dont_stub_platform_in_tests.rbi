# typed: true

module RuboCop
  module Cop
    module GitHub
      class DontStubPlatformInTests < Base
        def platform_stub_or_expect?(node)
        end
      end
    end
  end
end
