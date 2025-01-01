# typed: true
# frozen_string_literal: true

module Releases
  class EditButtonComponent < ApplicationComponent
    def initialize(release, repository, **system_arguments)
      @release = release
      @repository = repository
      @system_arguments = system_arguments
    end
  end
end
