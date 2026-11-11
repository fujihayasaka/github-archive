# typed: true
# frozen_string_literal: true

module Releases
  class DeleteButtonComponent < ApplicationComponent
    def initialize(release, current_repository, **system_arguments)
      @release = release
      @current_repository = current_repository
      @system_arguments = system_arguments
    end

    attr_reader :release, :current_repository, :system_arguments
  end
end
