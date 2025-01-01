# frozen_string_literal: true

class BackfillMissingSeveritiesJob < ApplicationJob
  queue_as :low

  # There are currently ~17K of these, seems reasonable to do in a few batches as this will be a very long-running job
  DEFAULT_LIMIT = 5000

  def perform(limit: DEFAULT_LIMIT, log: false)
    skipped_count = 0
    bugfix_date = DateTime.new(2023, 11, 1)
    reject_blocklist_terms = [1370, 1380] # terms based on NVDs reject language

    query = Advisory.includes(advisory_review: :blocklisted_terms)
      .joins(advisory_review: :feed_entries)
      .where(severity: nil, advisory_reviews: { state: :accepted }, feed_entries: { source: "nvd" })
      .where(feed_entries: { updated_at: ...bugfix_date })

    Rails.logger.info("#{query.count} Advisories to potentially update") if log

    if limit.present?
      query = query.limit(limit)
    end

    query.find_each do |advisory|
      if advisory.advisory_review.blocklisted_terms.where(id: reject_blocklist_terms).present?
        Rails.logger.info("Skipping Blocklisted Advisory: #{advisory.ghsa_id}") if log
        skipped_count += 1
        next
      elsif advisory.advisory_review.auto_closable?
        Rails.logger.info("Skipping Auto-Closeable Advisory: #{advisory.ghsa_id}") if log
        skipped_count += 1
        next
      elsif !advisory.advisory_review.accepted? # already queried for this but double check a curator didn't open the review in the meantime
        Rails.logger.info("Skipping Unaccepted Advisory: #{advisory.ghsa_id}") if log
        skipped_count += 1
        next
      end

      importer = NVDMissingSeverityImporter.new(cve_id: advisory.cve_id)

      begin
        importer.import
      rescue StandardError => error
        GitHub::Telemetry::Logs.logger.error(
          "Exception raised while running missing severity backfill",
          { exception: error, "gh.ghsa_id": advisory.ghsa_id },
        )
      end

      sleep(1) # NVD API rate limit
    end

    Rails.logger.info("Skipped #{skipped_count} Advisories") if log

    nil # silence the output
  end
end
