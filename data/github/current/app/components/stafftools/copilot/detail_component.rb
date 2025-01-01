# typed: true
# frozen_string_literal: true

class Stafftools::Copilot::DetailComponent < ApplicationComponent
  attr_reader :name, :note, :value, :label_scheme

  renders_one :body

  def initialize(name, value, note = nil, label_scheme: nil)
    @name = name
    @note = note
    @value = value
    @label_scheme = label_scheme
  end
end
