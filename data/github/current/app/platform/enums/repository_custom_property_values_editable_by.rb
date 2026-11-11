# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryCustomPropertyValuesEditableBy < Platform::Enums::Base
      description "The allowed actors who can edit the values of a custom property."

      value "ORG_ACTORS", "The organization actors.", value: "org_actors"
      value "ORG_AND_REPO_ACTORS", "The organization and repository actors.", value: "org_and_repo_actors"
    end
  end
end
