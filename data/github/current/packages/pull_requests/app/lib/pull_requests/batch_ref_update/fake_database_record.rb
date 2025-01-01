# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    # Placeholder data bag until the database migration completes.
    class FakeDatabaseRecord < T::Struct
      const :repository_id, Integer
      const :pull_request_id, Integer
      const :processing, T::Boolean, default: false
      const :ref_name, String
      const :before_sha, T.nilable(String)
      const :after_sha, String
      const :attempts, Integer, default: 0
      const :updated_at, Time, factory: -> { Time.current }
      const :created_at, Time, factory: -> { Time.current }
    end
  end
end
