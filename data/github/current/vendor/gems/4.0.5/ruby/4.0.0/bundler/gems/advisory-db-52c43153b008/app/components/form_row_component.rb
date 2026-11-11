# frozen_string_literal: true

class FormRowComponent < ApplicationComponent
  attr_reader :name, :value, :placeholder

  def initialize(name:, value: nil, placeholder: "", disabled: false)
    @name = name
    @value = value
    @placeholder = placeholder
    @disabled = disabled
  end

  def value?
    !value.nil?
  end
end
