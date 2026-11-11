# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryPermission < Platform::Enums::Base
      description "The access level to a repository"

      value "ADMIN", "Can read, clone, and push to this repository. Can also manage issues, pull requests, and repository settings, including adding collaborators", value: "admin"
      value "MAINTAIN", "Can read, clone, and push to this repository. They can also manage issues, pull requests, and some repository settings", value: "maintain"
      value "WRITE", "Can read, clone, and push to this repository. Can also manage issues and pull requests", value: "write"
      value "TRIAGE", "Can read and clone this repository. Can also manage issues and pull requests", value: "triage"
      value "READ", "Can read and clone this repository. Can also open and comment on issues and pull requests", value: "read"
    end
  end
end
