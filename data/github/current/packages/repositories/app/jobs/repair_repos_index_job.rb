# typed: strict
# frozen_string_literal: true

# The purpose of this job is to reconcile the state of Repository records
# between the database and the search index. We do this by iterating over
# each Repository, reading the state of the repository from the database
# and the search index, and then resolving the two based on their
# updated_at timestamps.
#
# Each repair job will process 250 repositories. When it has repaired all
# the repositories it will enqueue another job. This process will continue
# until all repositories have been repaired.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offest into the repository table is stored in redis. Access to
# this value is coordinated via a shared mutex. Don't spin up too many
# repair jobs otherwise you'll kill the database or the search index or
# both.
#
# There is a reids `enable` flag that the repair job checks to see if it
# should continue processing or die. This flag can be used to kill off all
# the repair jobs.
#
class RepairReposIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "repository",
    fields: %w[updated_at],
    limit: 250,
    accept: :repo_is_searchable?,
    include: %i(
      internal_repository
      mirror
      network
      repository_license
      owner
      topics
    ),
    prefills: %i(
      custom_properties_effective_values
      sponsorable_owner?
    )
end
