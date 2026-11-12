module API
  module Enums
    class DependencyScope < Types::BaseEnum
      description "The scope of a dependency"

      ::Types::Scope.each do |scope|
        value(scope.name, value: scope)
      end
    end
  end
end
