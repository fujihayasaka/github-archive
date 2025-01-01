# frozen_string_literal: true

class AffectedFunctionPayload
  include ActiveModel::Validations

  attr_reader :function

  def initialize(function)
    @function = function
  end
end
