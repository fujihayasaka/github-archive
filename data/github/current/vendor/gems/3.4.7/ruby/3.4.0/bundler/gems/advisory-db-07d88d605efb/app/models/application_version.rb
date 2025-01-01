# frozen_string_literal: true

class ApplicationVersion < ActiveRecord::Base # rubocop:disable Rails/ApplicationRecord
  include PaperTrail::VersionConcern
  include Diffable

  self.table_name = :versions

  belongs_to :user,
    foreign_key: :whodunnit,
    primary_key: :login,
    optional: true,
    inverse_of: false

  after_save :log_advisory_saves

  # Returns a descriptive symbol if the version represents an interesting event
  # in the life of this version's parent object. May return nil if this version
  # isn't interesting enough for inclusion in an activity timeline.
  #
  # Event names should be prefixed with the affected model and should have a
  # corresponding TimelineItemComponent subclass. See: TimelineItemComponent
  def event_name
    case item_type
    when Advisory.name
      case event
      when "create"
        if changeset.include?("reviewed") && !changeset.dig("reviewed", 1)
          :advisory_auto_publish
        else
          :advisory_publish
        end
      when "update"
        old_withdrawn = changeset.dig("withdrawn_at", 0)
        new_withdrawn = changeset.dig("withdrawn_at", 1)

        old_reviewed = changeset.dig("reviewed", 0)
        new_reviewed = changeset.dig("reviewed", 1)

        if new_withdrawn && !old_withdrawn
          :advisory_withdraw
        elsif new_reviewed && !old_reviewed
          :advisory_publish
        else
          :advisory_update
        end
      end
    when AdvisoryAlertingEvent.name
      case event
      when "create"
        :advisory_alerting_event_start_processing
      when "update"
        if changeset.include?("processed_at")
          :advisory_alerting_event_processed
        elsif changeset.include?("finished_at")
          :advisory_alerting_event_finished
        end
      end
    when AdvisoryReview.name
      case event
      when "create"
        :advisory_review_open
      when "update"
        old_withdrawn = changeset.dig("advisory_payload", 0, "withdrawn")
        new_withdrawn = changeset.dig("advisory_payload", 1, "withdrawn")

        if new_withdrawn && !old_withdrawn
          :advisory_review_withdraw
        elsif changeset.include?("state")
          old_state, new_state = changeset["state"]

          if new_state == "open" || (new_state == "in_review" && old_state != "open")
            :advisory_review_reopen
          elsif ["rejected", "closed"].include?(new_state) && ["rejected", "closed"].exclude?(old_state)
            :advisory_review_close
          elsif new_state == "accepted"
            :advisory_review_publish
          end
        else
          :advisory_review_update
        end
      end
    when AdvisoryReviewApproval.name
      case event
      when "create", "update"
        _old_approved_at, new_approved_at = changeset["approved_at"]

        if changeset.include?("approved_at") && new_approved_at
          :advisory_review_approve
        elsif changeset.include?("user_id")
          :advisory_review_assign
        end
      end
    when CVERequest.name
      case event
      when "create"
        :cve_request
      end
    when CVEReview.name
      case event
      when "create"
        :cve_review_open
      when "update"
        if changeset.include?("state")
          _, new_state = changeset["state"]
          case new_state
          when "submitted"
            :cve_review_publish
          when "notified"
            _, new_decision = changeset["decision"]
            if new_decision == "assigned"
              :cve_review_assign
            else
              :cve_review_close
            end
          when "open", "open_update"
            :cve_review_reopen
          when "rejected"
            :cve_review_reject
          end
        else
          :cve_review_update
        end
      end
    when FeedEntry.name
      case event
      when "create"
        :feed_entry_import
      when "update"
        non_process_changes = changeset.keys - ["resolution_state", "advisory_review_id", "updated_at"]
        if non_process_changes.present?
          :feed_entry_update
        end
      end
    when MITRECVESubmission.name
      case event
      when "create", "update"
        :cve_publish
      end
    when Vulnerability.name
      case event
      when "create"
        :vulnerability_publish
      when "update"
        old_withdrawn = changeset.dig("withdrawn_at", 0)
        new_withdrawn = changeset.dig("withdrawn_at", 1)

        if new_withdrawn && !old_withdrawn
          :vulnerability_withdraw
        else
          :vulnerability_update
        end
      end
    end
  end

  def log_advisory_saves
    # This is a temporary diagnostic method that is meant to capture advisory version saves.
    # We have seen strange behavior in the version history so we want to make sure it matches the authoritative object's save behavior.
    return unless item_type == Advisory.name

    ::GitHub::Telemetry::Logs.logger.info(
      "Logging a save of an Advisory Version Event",
      "gh.advisory_inbox.version.id": id,
      "gh.advisory_inbox.version.item_id": item_id,
      "gh.advisory_inbox.version.backtrace": caller.join(","),
      "gh.advisory_inbox.publisher.is_simulated": AdvisoryDB::GlobalVariables.in_simulated_publication?,
    )
  end

  def data
    return @data if defined? @data

    data = {}

    changeset.each do |key, (_, value)|
      data[key] = value
    end

    @data = NormalYAML.dump(data)
  end
end
