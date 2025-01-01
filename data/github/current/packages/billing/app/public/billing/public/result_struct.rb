# typed: strict
# frozen_string_literal: true
module Billing
  module Public
    class ResultStruct < T::Struct
      const :success, T::Boolean
      const :errors, T::Array[String], default: []
    end
  end
end
