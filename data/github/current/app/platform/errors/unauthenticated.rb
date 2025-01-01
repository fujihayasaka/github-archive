# typed: false
# frozen_string_literal: true

### !!! WARNING !!! ###
# This error should *only* be used
# if a user is missing/anonymous. If a user is lacking permissions,
# use the `Forbidden` error instead, which is more applicable to
# 99% of all cases.
module Platform
  module Errors
    class Unauthenticated < Errors::Execution
      def initialize(*args, **options)
        super("UNAUTHENTICATED", *args, **options)
      end
    end
  end
end
