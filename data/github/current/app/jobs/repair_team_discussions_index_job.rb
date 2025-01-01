# typed: true
# frozen_string_literal: true

# The purpose of this job is to reconcile the models with the index.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offset into the discussion_posts table is stored in redis.
# Access to this value is coordinated via a shared mutex. Don't spin up
# too many repair jobs otherwise you'll kill the database or the search
# index or both.
class RepairTeamDiscussionsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "team_discussion",
    fields: %w[updated_at],
    limit: 500,
    model_class: DiscussionPost
end
