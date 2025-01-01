# typed: strict
# frozen_string_literal: true

module Platform::Objects::Query::Sponsors
  extend ActiveSupport::Concern
  extend T::Helpers

  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :sponsorables, resolver: Platform::Resolvers::Sponsorables,
      description: "Users and organizations who can be sponsored via GitHub Sponsors.",
      connection: true,
      null: false do
      visibility :public, environments: [:dotcom]
      argument :order_by, Inputs::SponsorableOrder,
        "Ordering options for users and organizations returned from the connection.",
        required: false,
        default_value: { field: "login", direction: "ASC" }
      argument :only_dependencies, Boolean,
        "Whether only sponsorables who own the viewer's dependencies " \
        "will be returned. Must be authenticated to use. Can check an organization " \
        "instead for their dependencies owned by sponsorables by passing " \
        "orgLoginForDependencies.",
        default_value: false, required: false
      argument :org_login_for_dependencies, String,
        "Optional organization username for whose dependencies should be checked. Used when " \
        "onlyDependencies = true. Omit to check your own dependencies. If you are not an " \
        "administrator of the organization, only dependencies from its public repositories " \
        "will be considered.", required: false
      argument :dependency_ecosystem, Enums::SecurityAdvisoryEcosystem,
        "Optional filter for which dependencies should be checked for sponsorable owners. " \
        "Only sponsorable owners of dependencies in this ecosystem will be included. Used " \
        "when onlyDependencies = true.",
        required: false do
        deprecated(
          start_date: Date.new(2022, 3, 1),
          reason: "The type is switching from SecurityAdvisoryEcosystem to DependencyGraphEcosystem.",
          superseded_by: "Use the ecosystem argument instead.",
          owner: "cheshire137",
        )
      end
      argument :ecosystem, Enums::DependencyGraphEcosystem,
        "Optional filter for which dependencies should be checked for sponsorable owners. " \
        "Only sponsorable owners of dependencies in this ecosystem will be included. Used " \
        "when onlyDependencies = true.",
        required: false
    end
  end
end
