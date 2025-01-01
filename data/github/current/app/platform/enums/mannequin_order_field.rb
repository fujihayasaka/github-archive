# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MannequinOrderField < Platform::Enums::Base
      description "Properties by which mannequins can be ordered."

      value "LOGIN", "Order mannequins alphabetically by their source login.", value: "source_login"
      value "CREATED_AT", "Order mannequins why when they were created.", value: "created_at"
    end
  end
end
