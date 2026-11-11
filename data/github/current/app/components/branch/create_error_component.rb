# typed: true
# frozen_string_literal: true

class Branch::CreateErrorComponent < ApplicationComponent

  def initialize(message:)
    @message = message
  end

  def message
    @message
  end
end
