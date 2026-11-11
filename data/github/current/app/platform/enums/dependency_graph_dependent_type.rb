# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DependencyGraphDependentType < Platform::Enums::Base
      docs_category :dependency_graph
      description "The type of package dependent"
      visibility :internal

      value "REPOSITORY", "A repository dependent", value: :repository
      value "PACKAGE", "A package dependent", value: :package
    end
  end
end
