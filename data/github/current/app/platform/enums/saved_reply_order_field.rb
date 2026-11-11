# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SavedReplyOrderField < Platform::Enums::Base
      description "Properties by which saved reply connections can be ordered."

      value "UPDATED_AT", "Order saved reply by when they were updated.", value: "updated_at"
    end
  end
end
