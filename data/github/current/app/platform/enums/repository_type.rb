# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryType < Platform::Enums::Base
      graphql_name "RepositoryType"
      description "The different types of repositories that exist."
      mobile_only true

      value "PUBLIC", "Repositories that are visible to everyone.", value: "public"
      value "PRIVATE", "Repositories that are restricted to only certain users.", value: "private"
      value "SOURCE", "Repositories that are neither forks nor mirrors.", value: "source"
      value "FORK", "Repositories that are have been forked from other repositories.", value: "fork"
      value "MIRROR", "Repositories that are copied onto GitHub from other sites.", value: "mirror"
      value "TEMPLATE", "Repositories that can be used to generate new " \
        "repositories with the same directory structure, branches, and files.", value: "template"
      value "ARCHIVED", "Repositories that are no longer actively maintained.", value: "archived"
      value "SPONSORABLE", "Repositories owned by a user or organization who can be sponsored on GitHub Sponsors.",
        value: "sponsorable"
    end
  end
end
