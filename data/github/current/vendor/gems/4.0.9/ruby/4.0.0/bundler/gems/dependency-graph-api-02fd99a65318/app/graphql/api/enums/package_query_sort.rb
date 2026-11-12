module API
  module Enums
    class PackageQuerySort < Types::BaseEnum
      description "The types of sorts that can be run on package objects"

      value("ALPHABETICAL")
      value("DEFAULT")
      value("MOST_CERTAIN_REPOSITORY_ID")
      value("MOST_DEPENDENTS")
    end
  end
end
