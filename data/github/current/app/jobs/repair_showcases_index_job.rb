# typed: false
# frozen_string_literal: true

# The purpose of this job is to reconcile the state of ShowcaseCollections
# between the database and the search index. We do this by
# iterating over each ShowcaseCollection, reading the state of the showcase collection from
# the database and the search index, and then resolving the two based on
# their updated_at timestamps.
#
# Each repair job will process 250 showcase collections. When it has repaired all
# the showcase collections it will enqueue another job. This process will continue
# until all showcase collections have been repaired.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offset into the showcase collections table is stored in redis.
# Access to this value is coordinated via a shared mutex. Don't spin up
# too many repair jobs otherwise you'll kill the database or the search
# index or both.
#
# There is a redis `enable` flag that the repair job checks to see if it
# should continue processing or die. This flag can be used to kill off all
# the repair jobs.
class RepairShowcasesIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "showcase/collection",
    es_type: "showcase_collection",
    fields: %w[updated_at],
    limit: 250
end
