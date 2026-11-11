# typed: true

module RuboCop
  module Cop
    module GitHub
      class AvoidUsingStruct < Base
        def inherits_from_struct?(node)
        end

        def uses_open_struct?(node)
        end
      end
    end
  end
end
