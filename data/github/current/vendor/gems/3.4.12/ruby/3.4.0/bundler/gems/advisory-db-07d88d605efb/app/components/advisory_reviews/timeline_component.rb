# frozen_string_literal: true

module AdvisoryReviews
  class TimelineComponent < ::TimelineComponent
    MODELS_UPDATED_BY_PUBLICATION = ["Advisory", "Vulnerability"].freeze

    def items
      return @items if defined? @items

      items = []
      just_withdrawn = false

      versions.each do |version|
        item = TimelineItemComponent.for_version(version, subject: advisory_review)

        # Move on if the version isn't interesting enough to make the timeline.
        next unless item

        # Withdrawal produces two Paper Trail versions (one withdrawal and one
        # publication) but we only want the first one for the timeline.
        if just_withdrawn && item.event_name == :advisory_review_publish
          just_withdrawn = false
          next
        end

        # Track whether this item was a withdrawal event so we know whether to
        # exclude the next advisory review item if it's a publication event.
        if item.primary?
          just_withdrawn = item.event_name == :advisory_review_withdraw
        end

        # If this event is publishing the advisory review but the previous event
        # did not modify either the advisory or its vulnerabilities, we actually
        # reverted the review to its previously published state.
        if item.event_name == :advisory_review_publish
          last_modified = items.last.noun
          unless MODELS_UPDATED_BY_PUBLICATION.include?(last_modified)
            item = TimelineItemComponent::AdvisoryReviewRevert.new(
              version: version,
              event_name: :advisory_review_revert,
              subject: advisory_review,
            )
          end
        end

        items << item
      end

      @items = items
    end

    private

    def versions
      # Advisory review versions
      versions = advisory_review.versions.preload(:user).to_a

      # Feed entry versions
      advisory_review.feed_entries.preload(versions: :user).find_each do |feed_entry|
        versions.concat(feed_entry.versions)
      end

      # Advisory review approvals
      advisory_review.approvals.preload(versions: :user).find_each do |approval|
        versions.concat(approval.versions)
      end

      advisory = advisory_review.advisory
      if advisory
        # Advisory versions
        versions.concat(advisory.versions.preload(:user).to_a)

        # Vulnerability versions
        advisory.vulnerabilities.preload(versions: :user).find_each do |vulnerability|
          versions.concat(vulnerability.versions)
        end

        # Advisory Alerting Events
        advisory.advisory_alerting_events.preload(versions: :user).find_each do |advisory_alerting_event|
          versions.concat(advisory_alerting_event.versions)
        end
      end

      versions.sort_by!(&:id)
    end

    def advisory_review
      subject
    end
  end
end
