# typed: true
# frozen_string_literal: true

module Copilot
  class SignupComponent < ApplicationComponent
    renders_one :heading
    renders_one :new_heading
    renders_one :subheading
    renders_one :main

    def initialize(fullscreen: false)
      @fullscreen = fullscreen
    end
  end
end
