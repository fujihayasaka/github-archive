# typed: true
# frozen_string_literal: true
module Memex
  class ProjectNewButtonComponent < ApplicationComponent
    attr_reader :new_classic_project_path, :new_memex_path, :disable_classic_project_creation, :classes

    def initialize(new_classic_project_path:, new_memex_path:, disable_classic_project_creation: false, classes: "")
      @new_classic_project_path = new_classic_project_path
      @new_memex_path = new_memex_path
      @disable_classic_project_creation = disable_classic_project_creation
      @classes = classes
    end
  end
end
