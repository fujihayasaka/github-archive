# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class MannequinOrder < Platform::Inputs::Base
      description "Ordering options for mannequins."

      argument :field, Enums::MannequinOrderField,
        "The field to order mannequins by.",
        required: true

      argument :direction, Enums::OrderDirection,
        "The ordering direction.",
        required: true
    end
  end
end
