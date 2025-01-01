# typed: strict
# frozen_string_literal: true

class AuthenticCommit < ApplicationRecord::Domain::RepositoriesPushes
  extend T::Sig

  BULK_INSERT_SIZE = 1_000
  self.primary_key = [:network_id, :oid]

  serialize :oid, coder: GitHub::Hex

  # Bulk inserts commits into table, ignoring duplicates. Returns the total number of new rows that were actually
  # inserted.
  sig { params(commits: T::Array[{ network_id: Integer, oid: String, verified_at: Time }]).void }
  def self.bulk_insert(commits)
    # sort by network_id and oid to prevent deadlocks from ignoring duplicate inserts
    to_insert = commits.sort_by { |c| [c[:network_id], c[:oid]] }

    # setting on_duplicate to oid=oid produces a no-op in mysql if the rows are duplicated (because it's telling
    # mysql to set the oid column to itself, which is ignored)
    to_insert.each_slice(BULK_INSERT_SIZE) do |slice|
      AuthenticCommit.upsert_all(slice, on_duplicate: Arel.sql("`oid`=`oid`")) # rubocop:disable GitHub/UpsertAll
    end
  end
end
