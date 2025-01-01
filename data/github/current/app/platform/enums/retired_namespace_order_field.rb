# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RetiredNamespaceOrderField < Platform::Enums::Base
      description "Properties by which retired namespace connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Allows ordering a list of namespaces by the `created_at` value.", value: "created_at"
    end
  end
end
