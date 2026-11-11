# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class StarredRepositoryType < Platform::Enums::Base
      graphql_name "StarredRepositoryType"
      description "The different types of starred repositories that exist."
      visibility :under_development

      value "PUBLIC", "Repositories that are visible to everyone.", value: "public"
      value "PRIVATE", "Repositories that are restricted to only certain users.", value: "private"
      value "SOURCE", "Repositories that are neither forks nor mirrors.", value: "source"
      value "FORK", "Repositories that are have been forked from other repositories.", value: "fork"
      value "MIRROR", "Repositories that are copied onto GitHub from other sites.", value: "mirror"
      value "TEMPLATE", "Repositories that can be used to generate new " \
        "repositories with the same directory structure, branches, and files.", value: "template"
      value "SPONSORABLE", "Repositories owned by a user or organization who can be sponsored on GitHub Sponsors.",
        value: "sponsorable"
    end
  end
end
