# frozen_string_literal: true

class ResolveFeedEntryJob < ApplicationJob
  queue_as :default

  # Resolve feed entry is a messily enqueued job that could end up with multiple jobs trying to write at the same time.
  # It has been observed as firing record not unique and that makes sense, since a transaction could overlap and end up erroring.
  retry_on ActiveRecord::RecordNotUnique, attempts: 2, wait: :polynomially_longer

  def perform(feed_entry_id)
    feed_entry = FeedEntry.mark_as_resolving(feed_entry_id)
    if feed_entry.nil?
      return ::GitHub::Telemetry::Logs.logger.info(
        "Could not find feed entry to resolve",
        "gh.advisory_inbox.feed_entry.id": feed_entry_id,
      )
    end

    # the hydro message below wants to know if this was a new feed entry or not
    is_new_feed_entry = feed_entry.advisory_review_id.nil?
    if is_new_feed_entry
      ::GitHub::Telemetry::Logs.logger.info(
        "Resolving new feed entry",
        "gh.advisory_inbox.feed_entry.id": feed_entry_id,
      )
    else
      ::GitHub::Telemetry::Logs.logger.info(
        "Resolving updated feed entry",
        "gh.advisory_inbox.feed_entry.id": feed_entry_id,
        "gh.ghsa_id": feed_entry.advisory_review_id,
      )
    end

    needs_republish = false
    AdvisoryReview.transaction do
      _, needs_republish = AdvisoryReviewFeedEntryMerger.merge(feed_entry)
      feed_entry.mark_as_resolved
    end

    if needs_republish
      # Why is this scheduling for a minute from now? We appear to get duplicate key errors from double publishing too close together.
      # This is strange, but having a reasonable delay should prevent it. Since this is a sanity check republish, this is OK.
      # When we address https://github.com/github/team-advisory-database/issues/4624 this will go away, so this hack will naturally expire.
      # Note that the duplicate key errors don't ALWAYS happens, so this appears to be a race of some sort.
      PublishAdvisoryToHydroJob.set(wait: 1.minute).perform_later(feed_entry.advisory_review.advisory)
    end

    # only call CAPI (to do prediction) when feature flag is enabled, and advisory
    # is newly opened, and its source has "ai_prediction" config as "true"
    advisory_review = feed_entry.advisory_review
    if advisory_review &&
       AdvisoryDB::Features.enabled?("gpt4_prediction") &&
       advisory_review.curation_state == "open_create" &&
       AdvisoryDB.ai_prediction_sources.include?(feed_entry.source)
      Gpt4EcosystemPackagePredictionJob.perform_later(advisory_review_id: advisory_review.id, feed_entry_id: feed_entry.id)
    end

    ::GitHub::Telemetry::Logs.logger.info(
      "Resolved feed entry",
      "gh.advisory_inbox.feed_entry.id": feed_entry_id,
      "gh.ghsa_id": feed_entry.reload.advisory_review_id,
    )

    # Publish a Hydro message notifying feed entry was imported
    # Used by ML curation model, it will return an advisory prediction based on feed entry
    # NOTE: This is done here because it is important this not be published until there is an advisory review for the feed entry.
    #       otherwise the ML model could respond with a reject prediction before the advisory review is made
    PublishImportFeedEntryToHydroJob.perform_later(feed_entry, created: is_new_feed_entry)
  rescue StandardError => error
    # capture for logging
    @error = error
    raise error
  ensure
    if feed_entry&.resolving?
      begin
        ::GitHub::Telemetry::Logs.logger.error(
          "Failed to resolve feed entry",
          exception: @error,
          "gh.advisory_inbox.feed_entry.id": feed_entry_id,
          "gh.ghsa_id": feed_entry.advisory_review_id,
        )
        feed_entry.mark_as_unresolved
      rescue StandardError => error
        ::GitHub::Telemetry::Logs.logger.error(
          "Failed to mark feed entry as unresolved",
          exception: error,
          "gh.advisory_inbox.feed_entry.id": feed_entry_id,
          "gh.ghsa_id": feed_entry.advisory_review_id,
        )
      end
    end
  end
end
