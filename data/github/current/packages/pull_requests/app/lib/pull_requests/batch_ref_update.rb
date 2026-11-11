# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    # TODO: Replace this with the new database model once the migration finishes.
    DatabaseRecord = T.type_alias { FakeDatabaseRecord }
  end
end
