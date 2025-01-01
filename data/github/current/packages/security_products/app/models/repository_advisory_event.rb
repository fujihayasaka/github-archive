# typed: true
# frozen_string_literal: true

# Records events that occur around a RepositoryAdvisory.
# Attributes
# integer   :repository_advisory_id
# integer   :actor_id
# string    :event
# string    :changed_attribute
# string    :value_was
# string    :value_is
class RepositoryAdvisoryEvent < ApplicationRecord::Collab
  include RepositoryAdvisory::AfterPublication
  include RepositoryAdvisory::DeliverableNotificationSubscribers
  include Instrumentation::Model
  include NotificationsContent::WithoutCallbacks

  # Sorbet Includes
  include RepositoryAdvisory::DeliverableNotificationSubscribers::NotifiableComment

  attribute :value_was, StringFromBinary.new
  attribute :value_is, StringFromBinary.new

  belongs_to :repository_advisory
  belongs_to :actor, class_name: "User", foreign_key: :actor_id, inverse_of: false

  # This is for tracking a user who was added as a collaborator. Can be User or Team.
  belongs_to :subject, polymorphic: true, required: false

  VALID_EVENTS = %w[
    accepted
    closed
    collaborator_added
    collaborator_removed
    credit_accepted
    credit_assigned
    credit_declined
    credit_type_changed
    credit_unassigned
    cve_assigned
    cve_not_assigned
    cve_requested
    github_published
    github_rejected
    github_withdrawn
    published
    renamed
    reopened
    workspace_created
    workspace_deleted
  ].freeze

  NOTIFIABLE_EVENTS = %[
    accepted
    closed
    collaborator_added
    collaborator_removed
    credit_type_changed
    published
    reopened
  ].freeze

  # Create predicate method for each valid event name
  VALID_EVENTS.each do |event_name|
    define_method("#{event_name}?") do
      T.bind(self, RepositoryAdvisoryEvent)
      event == event_name
    end

    scope event_name, -> { where(event: event_name) }
  end

  # Not all of these are actual attributes on RepositoryAdvisory
  VALID_CHANGED_ATTRIBUTES = %w[
    collaborator
    credit
    cve_id
    review_state
    state
    title
    report_state
    workspace_repository_id
  ].freeze

  INSTRUMENTED_EVENTS = {
    cve_assigned: :cve_assignment,
    cve_not_assigned: :declined_cve_assignment,
    cve_requested: :cve_request,
    github_published: :github_broadcast,
    github_withdrawn: :github_withdraw,
  }

  validates :repository_advisory, presence: true
  validates :actor, presence: true
  validates :event, inclusion: VALID_EVENTS, presence: true
  validates :changed_attribute, inclusion: VALID_CHANGED_ATTRIBUTES, presence: true

  after_create :instrument_cve_decision_time
  after_commit :instrument_event, on: :create
  after_commit :subscribe_and_notify, on: :create

  def name
    event
  end

  def credit_event?
    credit_accepted? || credit_declined? || credit_assigned? || credit_unassigned? || credit_type_changed?
  end

  def readable_by?(viewer)
    async_readable_by?(viewer).sync
  end

  def async_readable_by?(viewer)
    # Non-collaborators are allowed to see their own advisory credit events,
    # but no other events.
    if credit_event? && viewer.is_a?(User) && viewer.id == actor_id
      return Promise.resolve(true)
    end

    async_repository_advisory.then do |advisory|
      # Collaborators are allowed to see advisory events.
      T.must(advisory).async_writable_by?(viewer).then do |writable|
        next Promise.resolve(false) unless writable

        # We should not expose events for teams that are not visible to the viewer.
        if (collaborator_added? || collaborator_removed?) && subject.is_a?(Team)
          next subject.async_visible_to?(viewer)
        end

        Promise.resolve(true)
      end
    end
  end

  def repository
    async_repository.sync
  end

  def async_repository
    async_repository_advisory.then { |x| T.must(x).async_repository }
  end

  def instrument_event
    instrument INSTRUMENTED_EVENTS[event.to_sym] if INSTRUMENTED_EVENTS.keys.include?(event.to_sym)
  end

  def event_payload
    T.must(repository_advisory).event_payload
  end

  def event_prefix
    :repository_advisory
  end

  # Notifications

  def message_id
    "<#{repository.name_with_display_owner}/repository-advisories/#{T.must(repository_advisory).id}/events/#{id}@#{GitHub.urls.host_name}>"
  end

  def get_notification_summary
    T.must(repository_advisory).get_notification_summary
  end

  def notifications_thread
    repository_advisory
  end

  def notifications_author
    actor
  end

  def user
    actor
  end

  def user_id
    user.id
  end

  # Public: Register the recipient for this notification
  #
  # id - The User ID for the recipient
  #
  # Returns nothing
  def register_recipient(id)
    @recipient = User.find_by(id: id)
  end
  attr_reader :recipient

  def body
    body = case
    when collaborator_added?
      if subject != recipient
        "@#{T.must(actor).display_login} added @#{subject&.name_with_display_owner} as a collaborator on: #{repository.name_with_display_owner} #{T.must(repository_advisory).title} (#{T.must(repository_advisory).ghsa_id})".dup
      else
        "@#{T.must(actor).display_login} added you as a collaborator on: #{repository.name_with_display_owner} #{T.must(repository_advisory).title} (#{T.must(repository_advisory).ghsa_id})".dup
      end
    when collaborator_removed?
      if subject != recipient
        "@#{T.must(actor).display_login} removed @#{subject&.name_with_display_owner} as a collaborator on: #{repository.name_with_display_owner} #{T.must(repository_advisory).title} (#{T.must(repository_advisory).ghsa_id})".dup
      else
        "@#{T.must(actor).display_login} removed you as a collaborator on: #{repository.name_with_display_owner} #{T.must(repository_advisory).title} (#{T.must(repository_advisory).ghsa_id})".dup
      end
    when credit_type_changed?
      "Your credit type on security advisory #{T.must(repository_advisory).ghsa_id} in #{repository.name_with_display_owner} has been changed from #{value_was} to #{value_is}."
    else
      "#{event.titlecase} #{T.must(repository_advisory).ghsa_id}."
    end

    ERB::Util.force_escape(body)
  end

  def subscribe_and_notify
    return unless NOTIFIABLE_EVENTS.include?(event)

    # For credit_type_changed events, only send a notification to the recipient.
    if credit_type_changed?
      GitHub.newsies.trigger(self, event_time: Time.now, reason: subscribable_event_to_reason(event), recipient_ids: [subject_id])
      return
    end

    # subscribers excluding PVR author if not a collaborator
    SubscribeAndNotifyJob.perform_later(
      self,
      subscriber_reasons_and_ids: subscriber_reasons_and_ids,
      deliver_notifications: ::GitHub.send_notifications?,
    )

    # unsubscribed PVD-author also gets some event notifications
    if T.must(repository_advisory).external? && T.must(repository_advisory).author && !T.must(repository_advisory).collaborator?(T.must(repository_advisory).author)
      state_changed = accepted? || closed? || reopened? || published?
      pvd_submitter_removed = collaborator_removed? && T.must(repository_advisory).user_is_pvd_submitter?(subject)

      if state_changed || pvd_submitter_removed
        GitHub.newsies.trigger(self, event_time: Time.now, reason: subscribable_event_to_reason(event), recipient_ids: [T.must(repository_advisory).author_id])
      end
    end
  end

  def subscriber_reasons_and_ids
    subscriber_ids = []

    if collaborator_added?
      case subject
      when Team
        subscriber_ids = subscribable_team_members(subject).pluck(:id)
      when User
        subscriber_ids = [subject.id]
      end
    end

    if subscriber_ids.present?
      {
        subscribable_event_to_reason(event) => subscriber_ids,
      }
    else
      nil
    end
  end

  def subscribable_event_to_reason(event)
    case event
    when "collaborator_added" then :assign
    else :state_change
    end
  end

  def async_notifications_list
    async_repository
  end

  def async_organization
    async_repository.then(&:async_organization)
  end

  def async_entity
    async_repository
  end

  def entity
    repository
  end

  def permalink(include_host: true)
    "#{T.must(repository_advisory).permalink(include_host: include_host)}#event-#{id}"
  end

  def unsubscribable_users(users)
    T.must(repository_advisory).unsubscribable_users(users)
  end

  # Override newsies Summarizable::DeliverNotifications.
  def deliver_notifications(event_time: nil)
    GitHub.newsies.trigger(
      self,
      event_time: event_time || created_at,
      recipient_ids: deliverable_user_ids(comment_author_id: T.must(actor).id),
      reason: subscribable_event_to_reason(event),
    )
    true
  end

  private

  def instrument_cve_decision_time
    return unless cve_assigned? || cve_not_assigned?

    request_times = RepositoryAdvisoryEvent.
      where(repository_advisory_id: repository_advisory_id, event: "cve_requested").
      pluck(:created_at).
      compact

    return if request_times.empty?

    earliest_request_time = request_times.min
    latest_request_time = request_times.max
    tags = ["decision:#{event}"]

    GitHub.dogstats.timing_since(
      "repository_advisory_event.cve_decision.total_time",
      earliest_request_time,
      tags: tags,
    )

    GitHub.dogstats.timing_since(
      "repository_advisory_event.cve_decision.time",
      latest_request_time,
      tags: tags,
    )
  end
end
