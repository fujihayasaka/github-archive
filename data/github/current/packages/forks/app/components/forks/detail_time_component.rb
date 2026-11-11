# typed: true
# frozen_string_literal: true

class Forks::DetailTimeComponent < ApplicationComponent
  sig { params(label: String, time: Time).void }
  def initialize(label, time)
    @time = time
    @label = label
    @selector_label = label.parameterize(separator: "-")
  end

  private

  sig { returns(Time) }
  attr_reader :time

  sig { returns(String) }
  attr_reader :label, :selector_label
end
