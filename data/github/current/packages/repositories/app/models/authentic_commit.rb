# typed: strict
# frozen_string_literal: true

class AuthenticCommit < ApplicationRecord::Domain::RepositoriesPushes
  BULK_UPSERT_SIZE = 1_000
  self.primary_key = [:network_id, :oid]

  attr_readonly :network_id, :oid, :verified_at, :push_id

  serialize :oid, coder: GitHub::Hex

  # Bulk upserts commits into table.
  # A duplicate is a record having matching network_id and oid.
  # If a duplicate is found, the push_id and verified_at columns will be updated only if previously null.
  sig { params(commits: T::Array[{ network_id: Integer, oid: String, push_id: T.nilable(Integer), verified_at: T.nilable(Time) }]).void }
  def self.bulk_upsert(commits)
    # sort by network_id and oid to prevent deadlocks from ignoring duplicate inserts
    to_upsert = commits.sort_by { |c| [c[:network_id], c[:oid]] }

    on_duplicate_sql = <<~SQL
      verified_at = IFNULL(verified_at, VALUES(verified_at)),
      push_id = IFNULL(push_id, VALUES(push_id))
    SQL

    to_upsert.each_slice(BULK_UPSERT_SIZE) do |slice|
      upsert_all(slice, on_duplicate: Arel.sql(on_duplicate_sql)) # rubocop:disable GitHub/UpsertAll
    end
  end
end
