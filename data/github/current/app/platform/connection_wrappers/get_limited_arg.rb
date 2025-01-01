# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    module GetLimitedArg

      extend T::Helpers
      requires_ancestor { GraphQL::Pagination::Connection }

      # This private method was removed upstream, but we depended on it, so it's backported here.
      # @return [Integer, nil] `nil` if this argument is nil, otherwise, replace a negative value with zero.
      def get_limited_arg(arg_name)
        arg_value = arguments[arg_name]
        if arg_value.nil?
          nil
        elsif arg_value < 0
          0
        else
          arg_value
        end
      end
    end
  end
end
