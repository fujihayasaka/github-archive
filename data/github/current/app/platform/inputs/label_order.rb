# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class LabelOrder < Platform::Inputs::Base
      description "Ways in which lists of labels can be ordered upon return."

      argument :field, Enums::LabelOrderField, "The field in which to order labels by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order labels by the specified field.", required: true
    end
  end
end
