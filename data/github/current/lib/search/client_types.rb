# typed: true
# frozen_string_literal: true

module Search
  # ClientTypes contains an enumeration of all the types of searches visible in the search UX. The values
  # correspond to the allowed values of the `type` URL parameter.
  module ClientTypes
    extend self

    CODE = Types::CODE
    COMMIT = Types::COMMIT
    DISCUSSION = Types::DISCUSSION
    ISSUE = Types::ISSUE
    LABEL = Types::LABEL
    MARKETPLACE = Types::MARKETPLACE
    REGISTRY_PACKAGE = Types::REGISTRY_PACKAGE
    REPOSITORY = Types::REPOSITORY
    TOPIC = Types::TOPIC
    USER = Types::USER
    WIKI = Types::WIKI

    PULL_REQUEST = "PullRequests"

    ALL = [
      PULL_REQUEST
    ].concat(Types::ALL).freeze

    def search_type_as_singular(type)
      case type
      when Search::ClientTypes::CODE then "code"
      when Search::ClientTypes::COMMIT then "commit"
      when Search::ClientTypes::DISCUSSION then "discussion"
      when Search::ClientTypes::ISSUE then "issue"
      when Search::ClientTypes::LABEL then "label"
      when Search::ClientTypes::MARKETPLACE then "marketplace"
      when Search::ClientTypes::REGISTRY_PACKAGE then "package"
      when Search::ClientTypes::REPOSITORY then "repository"
      when Search::ClientTypes::TOPIC then "topic"
      when Search::ClientTypes::USER then "user"
      when Search::ClientTypes::WIKI then "wiki"
      when Search::ClientTypes::PULL_REQUEST then "pull request"
      else type
      end
    end
  end
end
