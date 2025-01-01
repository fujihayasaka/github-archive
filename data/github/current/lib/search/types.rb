# typed: true
# frozen_string_literal: true

module Search
  # Types contains an enumeration of all the types of searches we are able to perform.
  # In the legacy search experience, these correspond to the types visible in the search UX, and the value of each
  # constant matches the `type` URL parameter value for the legacy search experience.
  # In the new search experience, these only correspond to the type of search which will be performed; the UX is
  # more granular and the `type` URL parameter has additional values.
  module Types
    CODE = "Code"
    COMMIT = "Commits"
    DISCUSSION = "Discussions"
    ISSUE = "Issues"
    LABEL = "Labels"
    MARKETPLACE = "Marketplace"
    REGISTRY_PACKAGE = "RegistryPackages"
    REPOSITORY = "Repositories"
    TOPIC = "Topics"
    USER = "Users"
    WIKI = "Wikis"
    VULNERABILITIES = "Vulnerabilities"

    ALL = [
      CODE,
      COMMIT,
      DISCUSSION,
      ISSUE,
      LABEL,
      MARKETPLACE,
      REGISTRY_PACKAGE,
      REPOSITORY,
      TOPIC,
      USER,
      WIKI
    ].freeze
  end
end
