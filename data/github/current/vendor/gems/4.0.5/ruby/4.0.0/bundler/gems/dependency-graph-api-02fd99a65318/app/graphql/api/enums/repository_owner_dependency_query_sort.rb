module API
  module Enums
    class RepositoryOwnerDependencyQuerySort < Types::BaseEnum
      description "Different ways to sort dependencies loaded for a particular repository owner"

      value("PACKAGE_MANAGER", "Sort by the package manager name, ascending.",
        value: "package_manager")
      value("PACKAGE_NAME", "Sort by the package name, ascending.", value: "package_name")
      value("RECENTLY_PUBLISHED", "Sort by the package publish date, descending.",
        value: "recently_published")
      value("LEAST_RECENTLY_PUBLISHED", "Sort by the package publish date, ascending.",
        value: "least_recently_published")
      value("MOST_USED", "Sort by the package most used in the repository owner's repositories.",
        value: "most_used")
      value("LEAST_USED", "Sort dependencies such that the packages used in the fewest " \
        "repositories are first.", value: "least_used")
    end
  end
end
