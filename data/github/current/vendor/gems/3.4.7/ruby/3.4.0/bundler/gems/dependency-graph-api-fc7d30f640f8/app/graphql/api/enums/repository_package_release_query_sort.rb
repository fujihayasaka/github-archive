module API
  module Enums
    class RepositoryPackageReleaseQuerySort < Types::BaseEnum
      description "The types of sorts that can be run on repository package release objects"

      value("NEWEST")
      value("OLDEST")
      value("RECENTLY_UPDATED")
      value("LEAST_RECENTLY_UPDATED")
      value("MOST_DEPENDENTS")
      value("LEAST_DEPENDENTS")
      value("MOST_VULNERABILITIES")
      value("LEAST_VULNERABILITIES")
      value("DEFAULT")
    end
  end
end
