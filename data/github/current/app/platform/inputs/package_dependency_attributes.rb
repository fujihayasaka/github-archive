# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class PackageDependencyAttributes < Platform::Inputs::Base
      description "A package dependency contains the information needed to satisfy a dependency."
      visibility :internal

      argument :name, String, "Identifies the name of the dependency.", required: true
      argument :version, String, "Identifies the version of the dependency.", required: true
      argument :dependency_type, Enums::PackageDependencyType, "Identifies the type of dependency.", required: true
    end
  end
end
