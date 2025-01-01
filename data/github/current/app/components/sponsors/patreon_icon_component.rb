# typed: strict
# frozen_string_literal: true

module Sponsors
  class PatreonIconComponent < ApplicationComponent
    extend T::Sig

    sig { params(size: Integer, system_arguments: T::untyped).void }
    def initialize(size: 16, **system_arguments)
      @color = T.let(system_arguments[:color] || :default, Symbol)
      @classes = T.let(system_arguments[:classes] || "octicon", String)
      @width = T.let(system_arguments[:width] || size, Integer)
      @height = T.let(system_arguments[:height] || size, Integer)
      @system_arguments = T.let(system_arguments, T::untyped)
    end

    private

    sig { returns T::untyped }
    attr_reader :system_arguments

    sig { returns Symbol }
    attr_reader :color

    sig { returns String }
    attr_reader :classes

    sig { returns Integer }
    attr_reader :height

    sig { returns Integer }
    attr_reader :width

    sig { returns T::Boolean }
    def render?
      GitHub.sponsors_enabled?
    end
  end
end
