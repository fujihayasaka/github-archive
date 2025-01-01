# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class CommitAuthor < Platform::Inputs::Base
      description "Specifies an author for filtering Git commits."

      argument :id, ID, "ID of a User to filter by. If non-null, only commits authored by this user will be returned. This field takes precedence over emails.", required: false

      argument :emails, [String], "Email addresses to filter by. Commits authored by any of the specified email addresses will be returned.", required: false
    end
  end
end
