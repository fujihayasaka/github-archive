# typed: true
# frozen_string_literal: true

class Platform::Models::CodeSearchLanguage
  attr_reader :name, :id, :color

  def initialize(name:, id:, color:)
    @name  = name.to_s
    @id    = id.to_i
    @color = color.to_s
  end
end
