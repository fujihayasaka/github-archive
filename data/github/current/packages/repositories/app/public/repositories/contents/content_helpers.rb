# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    module ContentHelpers
      sig { params(spokes_object_type: T.any(Symbol, Integer)).returns(Symbol) }
      def self.git_contents_type(spokes_object_type)
        case spokes_object_type
        when :TYPE_TREE
          :tree
        when :TYPE_BLOB
          :blob
        when :TYPE_COMMIT
          :submodule
        else
          raise "unexpected object type: #{spokes_object_type}"
        end
      end
    end
  end
end
