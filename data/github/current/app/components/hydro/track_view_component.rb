# typed: strict
# frozen_string_literal: true

module Hydro
  class TrackViewComponent < ApplicationComponent
    extend T::Sig

    sig { params(name: String).void }
    def initialize(name:)
      @name = name
    end

    private

    sig { returns(String) }
    attr_reader :name
  end
end
