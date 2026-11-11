# typed: strict
# frozen_string_literal: true

module Providers
  class AppleIconComponent < ApplicationComponent
    sig { params(size: Integer, system_arguments: T::untyped).void }
    def initialize(size: 16, **system_arguments)
      @width = T.let(system_arguments[:width] || size, Integer)
      @height = T.let(system_arguments[:height] || size, Integer)
      @classes = T.let(system_arguments[:classes] || "octicon", String)
      @system_arguments = T.let(system_arguments, T::untyped)
    end

    private

    sig { returns String }
    attr_reader :classes

    sig { returns T::untyped }
    attr_reader :system_arguments

    sig { returns Integer }
    attr_reader :height

    sig { returns Integer }
    attr_reader :width
  end
end
