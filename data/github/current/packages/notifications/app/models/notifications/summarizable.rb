# typed: true
# frozen_string_literal: true

# Behavior that describes how Comments update the Newsies Summary data.
# Models should include this after all other callbacks.  This ensures that the
# notifications going out are for the finalized model.
module Notifications
  module Summarizable
    extend T::Helpers

    abstract!

    requires_ancestor { ActiveRecord::Base }

    # Provide subclasses a hook for preventing the delivery of notifications.
    # PullRequestReviewComments that belong to an open PullRequestReview should
    # not notify per comment, only when the review is submitted.
    #
    # Returns true if notifications are allowed to be sent for this model creation.
    sig { returns T::Boolean }
    def deliver_notifications?
      true
    end

    # Public: Should the update_notification_summary happen?
    #
    # See also PullRequestReviewComment#update_notification_summary?
    #
    # Returns Boolean-ish
    sig { returns T.nilable(T::Boolean) }
    def update_notification_summary?
      related_repo_exists_when_defined
    end

    # If the model defines a `:repository` relation, but no `repository` can be found
    # on the instance, do not allow the update callback to run.
    #
    # This prevents methods later in the callback from dereferencing a `nil` and causing
    # exceptions when attempting to call `#repository.*` (e.g. `#repository.permalink`)
    #
    # Returns a Boolean that is false when a repository is expected, but not found
    sig { returns T::Boolean }
    def related_repo_exists_when_defined
      # If we don't have a repository relation, move on
      return true if T.unsafe(self.class).reflect_on_association(:repository).nil?

      !T.unsafe(self).repository.nil?
    end

    # Public: Gets the NotificationSummary for this Comment's thread.
    #
    # Returns a NotificationSummary.
    def get_notification_summary
      raise NotImplementedError
    end

    # Public: updates the NotificationSummary with the updated contents
    # of this Comment's body.
    # Params:
    #   enqueue: defaults to true, whether to enqueue a job to update the summary
    # Returns a Boolean.
    sig { params(enqueue: T::Boolean).returns(T::Boolean) }
    def update_notification_summary(enqueue: true)
      if GitHub.flipper[:update_notification_summary_always_enqueue].enabled?
        update_notification_summary_always_enqueue(enqueue: enqueue)
      else
        update_notification_summary_enqueue_on_failure(enqueue: enqueue)
      end
    end

    sig { params(enqueue: T::Boolean).returns(T::Boolean) }
    def update_notification_summary_enqueue_on_failure(enqueue: true)
      succeeded = update_notification_summary_now
    ensure
      if !succeeded && enqueue
        enqueue_job
      end
    end

    sig { params(enqueue: T::Boolean).returns(T::Boolean) }
    def update_notification_summary_always_enqueue(enqueue: true)
      if enqueue
        enqueue_job
        true
      else
        update_notification_summary_now
      end
    end

    sig { void }
    def enqueue_job
      if GitHub.flipper[:update_notification_summary_with_locks].enabled?
        actor_id = self.try(:notifications_author)&.try(:id)
        GitHub.logger.info("Enqueuing job to update notification summary", {
          "gh.actor.id": actor_id,
          "gh.notifications_list.id": self.try(:notifications_list)&.try(:id),
          "gh.notifications_list.klass": self.try(:notifications_list)&.try(:class)&.try(:name),
          "gh.notifications_thread.id": self.try(:notifications_thread)&.try(:id),
          "gh.notifications_thread.klass": self.try(:notifications_thread)&.try(:class)&.try(:name),
        })

        UpdateNotificationSummaryWithLocksJob.perform_later(self.class.name, self.id, false, false, {
          actor_id: actor_id
        })
      else
        UpdateNotificationSummaryJob.perform_later(self.class.name, self.id, false, false)
      end
    end

    sig { returns T::Boolean }
    def update_notification_summary_now
      started_at = GitHub::Dogstats.monotonic_time

      get_response = get_notification_summary
      if get_response&.failed?
        track_update_notification_rollup_latency(started_at, "failed_on_get_summary")
        return false
      end

      summary = get_response.value
      if summary.nil?
        track_update_notification_rollup_latency(started_at, "missing_summary")
        # This should return a false if the summary is missing, but we don't want break the previous behavior
        return true
      end

      update_notification_rollup(summary)
      save_response = Newsies::Response.new { summary.save }
      if save_response.failed?
        track_update_notification_rollup_latency(started_at, "failed_on_save")
        return false
      end

      track_update_notification_rollup_latency(started_at, "succeeded")

      true
    end

    def track_update_notification_rollup_latency(started_at, status)
      duration = GitHub::Dogstats.duration(started_at)

      GitHub.dogstats.distribution(
        "notifications.update_notification_rollup.latency", duration,
        tags: ["subject_type:#{self.class.name}", "status:#{status}"]
      )

      GitHub.logger.info("updating rollup summary", {
        "code.namespace": "Summarizable",
        "code.function": "update_notification_summary_now",
        "gh.notifications.update_summary.subject_type": self.class.name,
        "gh.notifications.update_summary.subject_id": self.id,
        "gh.notifications.update_summary.status": status,
        "gh.notifications.update_summary.duration": duration,
        "gh.notifications_list.id": self.try(:notifications_list)&.try(:id),
        "gh.notifications_list.klass": self.try(:notifications_list)&.try(:class)&.try(:name),
        "gh.notifications_thread.id": self.try(:notifications_thread)&.try(:id),
        "gh.notifications_thread.klass": self.try(:notifications_thread)&.try(:class)&.try(:name),
      })
    end

    def update_notification_rollup(summary)
      suffix = summarizable_changed?(:body) ? :changed : :unchanged
      GitHub.dogstats.increment("newsies.rollup", tags: ["type:#{suffix}"])

      summary.summarize_comment(self)
    end

    # Public: Destroys the summarized content in this thread's
    # NotificationSummary.
    #
    # Returns nothing.
    sig { void }
    def destroy_notification_summary
      get_response = get_notification_summary
      if get_response && get_response.success?
        return unless summary = get_response.value
        summary.delete_item(self)
        Newsies::Response.new { summary.save! }
      end
    end

    # Public: Triggers the job to deliver notifications of this Comment after
    # creation.
    #
    # event_time              - Time that this notification was created. This is typically the `created_at` time
    #                           for notifications on creation, or `updated_at` if notifying about updates.
    #
    # Returns False if delivery did NOT happen
    # Returns True  if the delivery job was kicked off
    def deliver_notifications(event_time: nil)
      time = event_time
      time ||= T.unsafe(self).created_at if respond_to?(:created_at)
      GitHub.newsies.trigger(self, event_time: time)
      true
    end

    # Saves changed attributes in a `before_update` callback, so that `after_commit`
    # callbacks can access it.
    def get_changed_attributes_for_summary
      @summarizable_changes = Set.new(changed)
    end

    # Public: Returns true if any of the given attributes were changed.  Only
    # usable when the Summarizable record is being saved.  Otherwise, use the
    # core ActiveRecord dirty attributes API (#changed).
    def summarizable_changed?(*attrs)
      return unless @summarizable_changes
      attrs.any? { |a| @summarizable_changes.include?(a.to_s) }
    end
  end
end
