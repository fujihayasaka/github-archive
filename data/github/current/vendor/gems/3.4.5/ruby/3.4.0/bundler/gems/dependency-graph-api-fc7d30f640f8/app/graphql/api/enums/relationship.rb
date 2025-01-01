module API
  module Enums
    class Relationship < Types::BaseEnum
      description "Whether the dependency is direct or transitive"

      ::Types::Relationship.each do |relationship|
        value(relationship.name, value: relationship)
      end
    end
  end
end
