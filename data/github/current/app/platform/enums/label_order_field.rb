# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class LabelOrderField < Platform::Enums::Base
      description "Properties by which label connections can be ordered."

      value "NAME", "Order labels by name ", value: "name"
      value "CREATED_AT", "Order labels by creation time", value: "created_at"
    end
  end
end
