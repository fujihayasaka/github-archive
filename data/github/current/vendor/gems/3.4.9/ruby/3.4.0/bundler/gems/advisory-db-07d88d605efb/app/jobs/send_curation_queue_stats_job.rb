# frozen_string_literal: true

class SendCurationQueueStatsJob < ApplicationJob
  queue_as :low

  def perform
    calculate_cve_review_queue_depth

    AdvisoryDB.sources.each do |source|
      calculate_advisory_review_queue_depth source: source
    end
  end

  private

  def calculate_cve_review_queue_depth
    depth = CVEReview.open.count
    AdvisoryDB.stats.gauge("cve_review.queue.depth", depth)
  end

  def calculate_advisory_review_queue_depth(source:)
    advisory_reviews = AdvisoryReview.by_source(source).by_campaign(nil)
    update_depth = advisory_reviews.curation_state_open_update.count
    new_depth = advisory_reviews.curation_state_open_create.count

    AdvisoryDB.stats.gauge("advisory_review.queue.depth", new_depth, {
      tags: AdvisoryDB.dogtags(queue: source, new: "true"),
    })

    AdvisoryDB.stats.gauge("advisory_review.queue.depth", update_depth, {
      tags: AdvisoryDB.dogtags(queue: source, new: "false"),
    })
  end
end
