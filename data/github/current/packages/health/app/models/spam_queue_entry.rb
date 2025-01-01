# typed: false
# frozen_string_literal: true

class SpamQueueEntry < ApplicationRecord::Domain::Spam
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::SpamQueueEntry

  belongs_to :spam_queue
  belongs_to :user
  belongs_to :spam_source, polymorphic: true
  belongs_to :added_by, class_name: "User", foreign_key: "added_by_user_id" # rubocop:todo Rails/InverseOf
  belongs_to :locked_by, class_name: "User", foreign_key: "locked_by_user_id" # rubocop:todo Rails/InverseOf

  validates_presence_of :spam_queue
  validates_presence_of :user_login
  validates_presence_of :user_id
  validates_uniqueness_of :user_id, scope: :spam_queue_id

  # `additional_context` varchar(255) DEFAULT NULL,

  after_create_commit :instrument_creation, :notify_entry_created
  after_destroy_commit :instrument_deletion

  delegate :spammy?, :hammy?, to: :user, allow_nil: true

  scope :by_spam_queue_id, ->(spam_queue_id) { where(spam_queue_id: spam_queue_id) }
  scope :recent, -> (limit = 20) { order("id DESC").limit(limit) }
  scope :by_date, -> (date) {
    where(arel_table[:created_at].gteq(date)).where(arel_table[:created_at].lt(date + 1.day))
  }

  attr_accessor :origin_on_create

  extend GitHub::Encoding
  force_utf8_encoding :additional_context

  def notify_entry_created
    data = {
      spam_queue_id: spam_queue_id,
      entry_id: self.id,
      entry_user_id: self.user_id,
      entry_user_login: self.user_login,
      entry_user_extra: user_status,
      timestamp: created_at.to_i,
      wait: default_live_updates_wait,
    }
    channel = GitHub::WebSocket::Channels.spam_queue_changed(spam_queue)
    GitHub::WebSocket.notify_spam_queue_entry_channel(self, channel, data)
  end

  def user=(new_user)
    self.user_login = new_user && new_user.login
    super
  end

  # Public: Resolve this entry as spammy
  #         Results are reported to the Audit Log.
  #
  # reason          - The reason this user is spammy.
  # actor           - The User record of the person working the queue
  # hard_flag       - Set the hard flag marking this user as spam regardless
  #                   regardless of any whitelisting.
  def resolve_as_spammy(reason:, actor:, hard_flag: false, origin: nil)
    payload = resolve_payload(resolution: :flag_as_spam, actor: actor, reason: reason, origin: origin)
    payload[:hard_flag] = hard_flag

    destroy

    serialized_previous_data = user.hydro_spammy_and_suspended_data
    # If the user exists still, resolve this and mark them as spammy
    if user_exists?
      user.mark_as_spammy actor: actor, hard_flag: hard_flag, reason: reason, origin: origin,
        instrument_abuse_classification: false
      instrument :resolved, payload
    end

    GlobalInstrumenter.instrument "abuse_classification.publish", abuse_classification_hydro_payload(
      actor: actor,
      queue_action: :UNQUEUE,
      previous_queue: spam_queue,
      origin: origin,
      **serialized_previous_data,
    )
  end

  # Public: Resolve this spammy entry as not spammy and unflag it.
  #         Results are reported to the Audit Log.
  #
  # actor           - The User record of the person working the queue
  def resolve_as_unflagged(actor:, origin: nil)
    payload = resolve_payload(resolution: :unflag_as_spam, actor: actor, origin: origin)

    destroy

    serialized_previous_data = user.hydro_spammy_and_suspended_data

    # If the user exists still, resolve this and mark them as not_spammy/allowlisted
    if user_exists?
      user.mark_not_spammy actor: actor, origin: origin,
        instrument_abuse_classification: false
      instrument :resolved, payload
    end

    GlobalInstrumenter.instrument "abuse_classification.publish", abuse_classification_hydro_payload(
      actor: actor,
      queue_action: :UNQUEUE,
      previous_queue: spam_queue,
      origin: origin,
      **serialized_previous_data,
    )
  end

  # Public: Resolve this entry as whitelisted.
  #         Results are reported to the Audit Log.
  #
  # actor           - The User record of the person working the queue
  def resolve_as_whitelisted(actor:, origin: nil)
    payload = resolve_payload(resolution: :whitelist, actor: actor, origin: origin)

    destroy

    serialized_previous_data = user.hydro_spammy_and_suspended_data

    # If the user exists still, resolve this and mark them as not_spammy
    if user_exists?
      user.mark_not_spammy whitelist: true, actor: actor, origin: origin,
        instrument_abuse_classification: false
      instrument :resolved, payload
    end

    GlobalInstrumenter.instrument "abuse_classification.publish", abuse_classification_hydro_payload(
      actor: actor,
      queue_action: :UNQUEUE,
      previous_queue: spam_queue,
      origin: origin,
      **serialized_previous_data,
    )
  end

  def resolve(actor:, classification:, reason: nil, origin: nil)
    if user.present?
      self.user_exists = true

      case classification
      when :spammy
        resolve_as_spammy(actor: actor, reason: reason, origin: origin)
      when :hammy
        resolve_as_whitelisted(actor: actor, origin: origin)
      when :unknown
        if user.spammy?
          resolve_as_unflagged(actor: actor, origin: origin)
        else
          drop(actor: actor, origin: origin)
        end
      end

      user
    else # nil user
      serialized_previous_classification = Hydro::EntitySerializer.account_spammy_classification(user)
      serialized_previous_spammy_reason = Hydro::EntitySerializer.account_spammy_reason(user)
      serialized_previously_suspended = Hydro::EntitySerializer.account_suspended(user)

      destroy

      GlobalInstrumenter.instrument "abuse_classification.publish", abuse_classification_hydro_payload(
        actor: actor,
        queue_action: :UNQUEUE,
        previous_queue: spam_queue,
        origin: origin,
        serialized_previous_classification: serialized_previous_classification,
        serialized_previous_spammy_reason: serialized_previous_spammy_reason,
        serialized_previously_suspended: serialized_previously_suspended,
      )
      nil
    end
  end

  # Public: Drop this record from the queue
  #         No action is taken, and no audit record is tracked.
  def drop(actor:, origin: nil)
    serialized_previous_data = user.hydro_spammy_and_suspended_data

    destroy

    if instrument_abuse_classification?
      GlobalInstrumenter.instrument "abuse_classification.publish", abuse_classification_hydro_payload(
        actor: actor,
        queue_action: :UNQUEUE,
        previous_queue: spam_queue,
        origin: origin,
        **serialized_previous_data,
      )
    end

    instrument :drop, queued_time_in_seconds: queued_time_in_seconds, actor: actor
  end

  def platform_move_to_queue(new_queue:, actor:, reason: nil, origin: nil)
    payload = resolve_payload reason: reason, resolution: :move_queue, actor: actor, origin: origin
    payload[:old_queue_name] = spam_queue.name
    payload[:old_queue_id] = spam_queue.id

    previous_spam_queue = spam_queue
    @instrument_abuse_classification = false

    new_sqe = nil

    transaction do
      drop(actor: actor, origin: origin)
      new_sqe = new_queue.entries.create!({
        user_login: user_login,
        user_id: user_id,
        spam_source: spam_source,
        added_by: actor,
        additional_context: additional_context,
        origin_on_create: payload[:origin],
        instrument_abuse_classification: false,
      })
    end

    GlobalInstrumenter.instrument "abuse_classification.publish", new_sqe.abuse_classification_hydro_payload(
      actor: actor,
      queue_action: :MOVE_QUEUES,
      previous_queue: previous_spam_queue,
      origin: origin,
    ).merge(queued_time_in_seconds: queued_time_in_seconds)

    @instrument_abuse_classification = true
    new_sqe
  end

  # Public: Move this record to the end of the queue
  #         by dropping and recreating it.
  #
  # Returns the new SpamQueueEntry
  def move_to_end_of_queue
    previous_spam_queue = spam_queue
    @instrument_abuse_classification = false

    new_sqe = nil

    transaction do
      destroy
      new_sqe = spam_queue.entries.create user_login: user_login, user_id: user_id,
        spam_source: spam_source, added_by: added_by,
        additional_context: additional_context,
        created_at: created_at, updated_at: updated_at,
        instrument_abuse_classification: false
    end

    GlobalInstrumenter.instrument "abuse_classification.publish", new_sqe.abuse_classification_hydro_payload(
      actor: added_by,
      queue_action: :PUSH_TO_END,
      previous_queue: previous_spam_queue,
    ).merge(queued_time_in_seconds: queued_time_in_seconds)

    @instrument_abuse_classification = true
    new_sqe
  end

  # Public: Move this entry to another queue
  def move_to_queue(new_queue:, actor: nil, reason: nil)
    previous_spam_queue = spam_queue
    return if spam_queue == new_queue

    payload = resolve_payload reason: reason, resolution: :move_queue, actor: actor
    payload[:old_queue_name] = spam_queue.name
    payload[:old_queue_id] = spam_queue.id

    result = update spam_queue: new_queue
    if result
      GlobalInstrumenter.instrument "abuse_classification.publish", abuse_classification_hydro_payload(
        actor: actor,
        queue_action: :MOVE_QUEUES,
        previous_queue: previous_spam_queue,
        origin: nil,
      )

      instrument :move, payload
    end
    result
  end

  # Instrumentation event prefix
  def event_prefix
    :spam_queue_entry
  end

  # Instrumentation event payload
  def event_payload
    payload = {
      :queue_name => spam_queue.name,
      :queue_id => spam_queue_id,
      event_prefix => self,
      :origin => :dotcom,
      :timestamp => Time.now.utc,
    }

    if user
      payload[:user] = user
      payload[:user_type] = user.type
    else
      # No user_id is present, so just put the login here
      payload[:user] = user_login
    end

    payload[:added_by] = added_by if added_by
    payload[:additional_context] = additional_context if additional_context
    payload
  end

  # Public: Does the user attached to this entry still exist?
  #
  #         Sometimes users are deleted out from under us, so ensure we
  #         really have a user still.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def user_exists?
    @user_exists ||= User.exists?(user_id)
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
  attr_writer :user_exists

  def instrument_abuse_classification?
    return true if @instrument_abuse_classification.nil?
    @instrument_abuse_classification
  end
  attr_writer :instrument_abuse_classification

  # Public: Additional information useful when spam hunting
  #
  # Returns a Hash
  def additional_info
    @additional_info ||= Spam::AdditionalUserInfo.new(user).results
  end

  def abuse_classification_hydro_payload(
    actor:,
    queue_action:,
    previous_queue: nil,
    serialized_previous_classification: nil,
    serialized_previous_spammy_reason: nil,
    serialized_previously_suspended: nil,
    origin: nil
  )

    payload = {
      actor: actor,
      # @hktouw shakes his head in disgust, "please just add a comment". So here it is,
      # if the user account is no longer around to include in the payload hydrate a new user object
      # with the old user id and login for logging purposes.
      account: user || User.new.tap { |user| user.id = user_id; user.login = user_login },
      serialized_previous_classification: serialized_previous_classification,
      serialized_previous_spammy_reason: serialized_previous_spammy_reason,
      serialized_previously_suspended: serialized_previously_suspended,
      queue_action: queue_action,
      previous_queue: previous_queue,
      current_queue: persisted? ? spam_queue : nil,
      queue_entry: persisted? ? self : nil,
      queued_time_in_seconds: queued_time_in_seconds,
      origin: origin,
    }

    payload
  end


  private

  # The default resolve payload
  def resolve_payload(resolution:, actor:, reason: nil, origin: nil)
    payload = {
      queued_time_in_seconds: queued_time_in_seconds,
      actor: actor,
      actor_login: actor.try(:login),
      resolution: resolution,
    }

    payload[:reason] = reason if reason

    origin ||= Spam::Origin.call(origin)
    payload[:origin] = origin.upcase

    payload
  end

  def hydro_payload(actor:, event_type:, current_spam_queue: nil, previous_spam_queue: spam_queue, resolution: nil, spammy_reason: nil, origin: nil)
    payload = {
      actor: actor,
      spam_queue_entry: self,
      event_type: event_type,
      # @hktouw shakes his head in disgust, "please just add a comment". So here it is,
      # if the user account is no longer around to include in the payload hydrate a new user object
      # with the old user id and login for logging purposes.
      account: user || User.new.tap { |user| user.id = user_id; user.login = user_login },
      additional_context: additional_context,
    }

    payload[:previous_spam_queue] = previous_spam_queue if previous_spam_queue.present?
    payload[:current_spam_queue] = current_spam_queue if current_spam_queue.present?
    payload[:resolution] = resolution if resolution.present?
    payload[:spammy_reason] = spammy_reason if spammy_reason.present?
    payload[:resolution] = resolution if resolution.present?

    origin ||= Spam::Origin.call(origin)
    payload[:origin] = origin.upcase

    if event_type == :DROP || event_type == :RESOLVE
      payload[:queued_time_in_seconds] = queued_time_in_seconds.to_i
    end

    payload
  end

  # Private: Time spent in the queue
  #
  # This does simple math subtracting created_at from Time.now to
  # give a length of stay to this entry in the queue.
  def queued_time_in_seconds
    Time.zone.now.minus_with_coercion(created_at)
  end

  # Stats are handled in config/instrumentation/spam.rb
  def instrument_creation
    payload = hydro_payload(
      actor: added_by,
      event_type: :ADD,
      current_spam_queue: spam_queue,
      previous_spam_queue: nil,
      origin: origin_on_create,
    )

    if instrument_abuse_classification?
      GlobalInstrumenter.instrument "abuse_classification.publish", abuse_classification_hydro_payload(
        actor: added_by,
        queue_action: :ADD,
        origin: nil,
      )
    end

    instrument :create, {
      actor: payload[:actor],
      actor_login: payload[:actor_login],
      origin: payload[:origin],
    }
  end

  # Stats are handled in config/instrumentation/spam.rb
  def instrument_deletion
    instrument :destroy
  end

  def user_status
    if self.user && self.user.paid_plan?
      "$$"
    else
      (self.user && self.user.spammy? ? "S" : nil)
    end
  end
end
