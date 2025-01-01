# typed: true
# frozen_string_literal: true

class Codespaces::LoadingButtonComponent < ApplicationComponent
  OPENING_CODESPACE_TEXT = "Opening in codespace"
  CREATING_CODESPACE_TEXT = "Creating codespace"

  attr_reader :btn_class

  def initialize(action:, btn_class:)
    @action = action
    @btn_class = btn_class
  end

  def text
    case @action
    when :open
      OPENING_CODESPACE_TEXT
    when :create
      CREATING_CODESPACE_TEXT
    else
      raise ArgumentError, "Must provide a valid action"
    end
  end
end
