# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ReviewDismissalAllowances < Resolvers::Base
      type Connections::ReviewDismissalAllowance, null: false

      def resolve(**arguments)
        @object.review_dismissal_allowances.scoped
      end
    end
  end
end
