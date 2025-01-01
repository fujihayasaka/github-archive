# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CodespaceOrder < Platform::Inputs::Base
      description "Ordering options for codespace connections."
      visibility :internal

      argument :field, Enums::CodespaceOrderField, "The field to order codespaces by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
