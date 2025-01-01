# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# The purpose of this job is to reconcile the state of Users and
# Organizations between the database and the search index. We do this by
# iterating over each User, reading the state of the user from the
# database and the search index, and then resolving the two based on their
# `updated_at` timestamps.
#
# Each repair job will process 250 users. When it has repaired all the
# users it will enqueue another job. This process will continue until all
# users have been repaired.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offest into the users table is stored in redis. Access to
# this value is coordinated via a shared mutex. Don't spin up too many
# repair jobs otherwise you'll kill the database or the search index or
# both.
class RepairUsersIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "user",
    fields: %w[updated_at],
    limit: 250,
    accept: :searchable?
end
