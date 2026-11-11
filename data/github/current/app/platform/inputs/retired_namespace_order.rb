# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RetiredNamespaceOrder < Platform::Inputs::Base
      description "Ways in which retired namespace connections can be ordered."
      visibility :internal

      argument :field, Enums::RetiredNamespaceOrderField, "The field in which to order nodes by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order nodes.", required: true
    end
  end
end
