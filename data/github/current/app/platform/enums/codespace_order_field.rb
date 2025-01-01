# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CodespaceOrderField < Platform::Enums::Base
      description "Properties by which codespace connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order codespaces by creation time", value: "created_at"
    end
  end
end
