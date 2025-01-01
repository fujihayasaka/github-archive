module API
  module Types
    class Mutation < Types::BaseObject
      description "The root mutation of this schema"

      field :reassign_package, mutation: Mutations::ReassignPackage
    end
  end
end
