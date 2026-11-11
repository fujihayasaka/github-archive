# typed: true
# frozen_string_literal: true

# This module implements the methods expected to be present for an object to
# act as both a Newsies/notification "comment" and a "thread." An advisory
# credit fulfills both of those roles.
module AdvisoryCredit::NewsiesAdapter
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { AdvisoryCredit }

  CREDIT_TYPE_ARTICLEIZED = {
    "analyst" => "an analyst",
    "finder" => "a finder",
    "reporter" => "a reporter",
    "coordinator" => "a coordinator",
    "remediation_developer" => "a remediation developer",
    "remediation_reviewer" => "a remediation reviewer",
    "remediation_verifier" => "a remediation verifier",
    "tool" => "a tool",
    "sponsor" => "a sponsor",
    "other" => "other",
  }.freeze

  sig { returns Promise[T.nilable(Repository)] }
  def async_notifications_list
    async_repository_advisory.then do |repository_advisory|
      repository_advisory&.async_repository
    end
  end

  alias_method :async_entity, :async_notifications_list

  sig { returns T.nilable(Repository) }
  def notifications_list
    async_notifications_list.sync
  end

  alias_method :entity, :notifications_list

  sig { returns Promise[AdvisoryCredit] }
  def async_notifications_thread
    T.bind(self, AdvisoryCredit)
    Promise.resolve(self)
  end

  sig { returns AdvisoryCredit }
  def notifications_thread
    async_notifications_thread.sync
  end

  sig { returns Promise[T.nilable(User)] }
  def async_notifications_author
    async_creator
  end

  sig { returns T.nilable(User) }
  def notifications_author
    async_notifications_author.sync
  end

  sig { params(args: T.untyped).returns(Promise[String]) }
  def async_permalink(**args)
    async_repository_advisory.then do |repository_advisory|
      repository_advisory&.permalink(**args)
    end
  end

  sig { params(args: T.untyped).returns(String) }
  def permalink(**args)
    async_permalink(**args).sync
  end

  sig { returns String }
  def message_id
    "<advisory-credits/#{id}@#{GitHub.urls.host_name}>"
  end

  def get_notification_summary
    GitHub.newsies.web.find_rollup_summary_by_thread(notifications_list, notifications_thread)
  end

  sig { returns String }
  def notification_summary_title
    "Accept credit for contributing to a Security Advisory"
  end

  sig { returns String }
  def notification_summary_body
    if creator
      "#{creator} credited you as #{CREDIT_TYPE_ARTICLEIZED[credit_type]} for your contributions to security advisory #{ghsa_id}."
    else
      "You were credited as #{CREDIT_TYPE_ARTICLEIZED[credit_type]} for your contributions to security advisory #{ghsa_id}."
    end
  end

  # Send notification to the credited user when a credit is created.
  #
  # Note that this is controlled by RepositoryAdvisory#readable_by? which is
  # true when repository advisory is published _or_ when the credited user has
  # read access to the draft advisory (i.e. a collaborator on the advisory).
  #
  # The deliver_notifications method is also called after the parent repository
  # advisory is published. Newsies prevents duplicate notification deliveries.
  sig { void }
  def deliver_notifications
    skip_notification = T.let(false, T::Boolean)

    with_lock do
      skip_notification = !deliver_notifications?
      next if skip_notification

      notified_at = Time.current

      GitHub.newsies.trigger(
        self,
        recipient_ids: [recipient&.id].compact,
        reason: :security_advisory_credit,
        event_time: notified_at,
      )

      update!(notified_at: notified_at)
    end

    instrument_event(:notify) unless skip_notification
  end

  sig { returns T::Boolean }
  def deliver_notifications?
    pending? &&
      !notified? &&
      recipient_id != creator_id &&
      !!recipient &&
      !!repository_advisory&.readable_by?(recipient)
  end

  sig { returns String }
  def credit_type_articleized
    CREDIT_TYPE_ARTICLEIZED[credit_type.to_s]
  end
end
