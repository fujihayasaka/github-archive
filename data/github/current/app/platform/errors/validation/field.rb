# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Validation < Errors::Execution
      class Field < Errors::Execution
        attr_reader :field_name
        attr_reader :message

        def initialize(field_name, message)
          @field_name = field_name
          @message = message

          super(self.class.type, "#{field_name} #{message}")
        end

        def self.type
          "VALIDATION-FIELD"
        end

        def to_h
          super.merge({
            "field" => field_name.to_s,
          })
        end
      end
    end
  end
end
