# typed: false
# frozen_string_literal: true

class SpamQueue < ApplicationRecord::Domain::Spam
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  SpamQueueItem = Struct.new(:date, :count)
  POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID = "MDU6UXVldWUx".freeze
  SUSPICIOUS_OLDER_ACCOUNTS_GLOBAL_RELAY_ID = "MDU6UXVldWU0MQ==".freeze

  has_many :entries, -> { order("id ASC") }, class_name: "SpamQueueEntry"

  # Queue names will be in the form of a slug aka
  # new_user_triage, possible_spammers, etc
  validates_presence_of :name
  validates :name, unicode3: true
  validates :description, unicode3: true

  after_create_commit :instrument_creation
  after_destroy_commit :instrument_deletion

  def self.possible_spammer_queue
    begin
      SpamQueue.find_by_name(Spam::QueueDependency::POSSIBLE_SPAMMER_QUEUE_KEY) ||
        SpamQueue.create(name: Spam::QueueDependency::POSSIBLE_SPAMMER_QUEUE_KEY,
                         description: "List of Users needing human review for spamminess")
    rescue ActiveRecord::RecordNotUnique
      retry # rubocop:disable GitHub/UnboundedRetries https://github.com/github/github/issues/134041
    end
  end

  # Public: Entries with the user pre-loaded.
  def entries_with_user
    entries.includes(:user)
  end

  # Public: Entries with the user & profile pre-loaded.
  def entries_with_profile
    entries.includes(user: :profile)
  end

  # Public: Does this queue include the given user?
  #
  # Checks via the login.
  #
  # Returns the entry if found, else nil.
  def includes_user?(user)
    entry_for_user user
  end

  def entry_for_user(user)
    if user.respond_to? :login
      login = user.login
    elsif user.is_a? String
      login = user
    else
      login = nil
    end
    entries.where("user_id = ? OR user_login = ?", user.try(:id), login).first
  end

  # Public: Push a new record onto the queue
  #
  # We only require user, all other params are optional here.
  #
  # If an entry exists for the given user, return it.
  # Else create a new entry and return it.
  def push(user:, additional_context: nil, spam_source: nil, added_by: nil)
    return existing_entry = includes_user?(user) if existing_entry.present?

    self.entries.create user: user, added_by: added_by,
      additional_context: additional_context, spam_source: spam_source
  end

  # Public: Sets the new name
  #
  # This takes the new name given and converts it
  # into the form we want.  For example:
  # "New User Triage" => "new_user_triage"
  def name=(new_name)
    new_name = new_name.to_s.downcase
    new_name.gsub! " ", "_"
    super new_name
  end

  # Public: Human friendly version of name
  # new_user_triage -> New User Triage
  def human_name
    name.to_s.split("_").map { |word| word.capitalize }.join " "
  end

  # Instrumentation event prefix
  def event_prefix
    :spam_queue
  end

  # Instrumentation event payload
  def event_payload
    {
      :name => name,
      event_prefix => self,
    }
  end

  # Public: Get and lock entries for user. Gets entries that are unlocked OR
  # locked by requesting user OR the lock is older than locked_at_minimum value.
  #
  # count             - Integer (default 2)
  # locked_at_minimum - DateTime (default 2 minutes ago)
  # user              - User requesting entries
  #
  # Returns an Array of SpamQueueEntry.
  def get_and_lock_entries(count: 2, locked_at_minimum: 2.minutes.ago, previous_id: 0, user:)
    raise "Max count is 10" if count > 10

    ActiveRecord::Base.connected_to(role: :writing) do
      SpamQueue.transaction do
        select_options = {
          spam_queue_id: id,
          locked_by_user_id: user.id,
          locked_at_minimum: locked_at_minimum,
          count: Arel.sql(count.to_s),
          previous_id: previous_id,
        }
        select_sql = Arel.sql(<<-SQL, **select_options)
          SELECT * FROM (
            (
              SELECT *
              FROM spam_queue_entries
              WHERE spam_queue_id = :spam_queue_id
              AND id > :previous_id
              AND locked_by_user_id = :locked_by_user_id
              ORDER BY id ASC
              LIMIT :count
            )
            UNION
            (
              SELECT *
              FROM spam_queue_entries
              WHERE spam_queue_id = :spam_queue_id
              AND locked_at is null
              ORDER BY id ASC
              LIMIT :count
            )
            UNION
            (
              SELECT *
              FROM spam_queue_entries
              WHERE spam_queue_id = :spam_queue_id
              AND  locked_at < :locked_at_minimum
              ORDER BY id ASC
              LIMIT :count
            )
          ) as entry_ids
          ORDER BY id ASC
          LIMIT :count
          FOR UPDATE
        SQL

        entries = SpamQueueEntry.find_by_sql(select_sql)
        unless entries.empty?
          update_options = {
            locked_at: Time.now,
            locked_by_user_id: user.id,
            entry_ids: entries.map(&:id),
          }
          SpamQueueEntry.connection.update(Arel.sql(<<-SQL, **update_options))
            UPDATE spam_queue_entries
            SET locked_at = :locked_at, locked_by_user_id = :locked_by_user_id
            WHERE id IN (:entry_ids)
          SQL
        end

        entries
      end
    end
  end

  # Public: Get entry counts by spam queue and date for all spam queues.
  #
  # Returns a Hash.
  def self.spam_queue_date_counts
    ActiveRecord::Base.connected_to(role: :reading) do
      by_spam_queue_id = {}

      results = SpamQueueEntry.connection.select_all(<<-SQL)
        SELECT
          spam_queue_id,
          date(created_at) AS date,
          count(id) AS count
        FROM spam_queue_entries
        GROUP BY spam_queue_id, date(created_at)
        ORDER BY spam_queue_id ASC, date(created_at) ASC
      SQL

      results.each do |(spam_queue_id, date, count)|
        by_spam_queue_id[spam_queue_id] ||= []
        by_spam_queue_id[spam_queue_id] << SpamQueueItem.new(date: date, count: count)
      end

      by_spam_queue_id
    end
  end

  private

  # Stats are handled in config/instrumentation/spam.rb
  def instrument_creation
    instrument :create
  end

  # Stats are handled in config/instrumentation/spam.rb
  def instrument_deletion
    instrument :destroy
  end
end
