# typed: false
# frozen_string_literal: true

class Migration < ApplicationRecord::Domain::Migrations
  include GitHub::Relay::GlobalIdentification
  include Workflow
  include UrlHelpers

  MAX_RETRIES = 5.freeze
  TOKEN_SCOPE = "UserMigration"

  validates :owner_id, presence: true
  validates :guid, presence: true
  validates :state, presence: true

  belongs_to :owner, class_name: "User"
  belongs_to :creator, class_name: "User"
  belongs_to :business
  has_many :migratable_resources, primary_key: "guid", foreign_key: "guid" # rubocop:todo Rails/InverseOf
  has_many :migration_repositories
  has_many :repositories, through: :migration_repositories, disable_joins: true
  has_many :migratable_resource_reports, dependent: :delete_all
  has_many :mannequins, class_name: "User"

  has_one :file, -> { order("id DESC") }, class_name: "MigrationFile"

  scope :for_owner, ->(owner) { where(owner_id: owner.id) }
  scope :newest, -> { order("created_at desc") }

  include Instrumentation::Model
  after_create_commit :instrument_creation

  def instrument_creation
    instrument :create
  end

  def platform_type_name
    "LegacyMigration"
  end

  # Public: Destroy migration file and instrument.
  def destroy_file
    if file
      file.destroy
      instrument :destroy_file
    end
  end

  workflow :state do
    state :pending, 0 do
      event :failed, transitions_to: :failed
      event :exporting, transitions_to: :exporting
      event :begin_prepare, transitions_to: :preparing
      event :begin_map, transitions_to: :mapping
      event :begin_import, transitions_to: :importing
      event :exported, transitions_to: :exported
    end

    state :exporting, 1 do
      event :exporting, transitions_to: :exporting
      event :upload_archive, transitions_to: :export_archive_uploaded
      event :exported, transitions_to: :exported
      event :failed, transitions_to: :failed
    end

    state :exported, 2

    state :failed, 3 do
      event :retry_export, transitions_to: :exporting
    end

    state :failed_import, 10 do
      event :retry_import, transitions_to: :pending
    end

    state :waiting, 40 do
      event :upload_archive, transitions_to: :archive_uploaded
    end

    state :archive_uploaded, 50 do
      event :upload_archive, transitions_to: :archive_uploaded
      event :prepare, transitions_to: :pending
    end

    state :export_archive_uploaded, 51 do
      event :exported, transitions_to: :exported
      event :failed, transitions_to: :failed
    end

    state :preparing, 60 do
      event :no_conflicts_detected, transitions_to: :ready
      event :conflicts_detected, transitions_to: :conflicts
      event :failed, transitions_to: :failed
      event :prepare, transitions_to: :pending
    end

    state :conflicts, 70 do
      event :enqueue_map, transitions_to: :pending
    end

    state :mapping, 75 do
      event :conflicts_detected, transitions_to: :conflicts
      event :resolve_conflicts, transitions_to: :ready
      event :failed, transitions_to: :failed
    end

    state :ready, 80 do
      event :import, transitions_to: :pending
      event :conflicts_detected, transitions_to: :conflicts
      event :resolve_conflicts, transitions_to: :ready
      event :enqueue_map, transitions_to: :pending
    end

    state :importing, 90 do
      event :import, transitions_to: :pending
      event :complete_import, transitions_to: :imported
      event :failed_import, transitions_to: :failed_import
    end

    state :imported, 100
    event :unlock, transitions_to: :unlocked

    state :unlocked, 110

    if Rails.env.test?
      # Adds a fake state for authz tests with fake transitions to itself
      state :authz_test, 120
      event :prepare, transitions_to: :authz_test
      event :import, transitions_to: :authz_test
      event :unlock, transitions_to: :authz_test
      event :resolve_conflicts, transitions_to: :authz_test
      event :enqueue_map, transitions_to: :authz_test
      event :begin_map, transitions_to: :authz_test
      event :failed, transitions_to: :authz_test
    end

    on_transition do |from, to, _event, *_event_args, **_kwargs|
      # Clear caches associated with migration state
      touch
      instrument(:state_changed,
        new_state: to,
        previous_state: from,
      )
    end
  end

  def self.workflow_state(name)
    workflow_spec.states[name]
  end

  def event_payload
    payload = {
      migration_id: id,
      started_by: creator,
      repo: [],
      repo_id: [],
      # public_repo is hardcoded to true here since we do not want to
      # expose the ip of the actor.
      public_repo: true,
    }.tap do |p|
      p[owner.event_prefix] = owner if owner
    end

    repositories.each_with_index do |repo, _i|
      payload[:repo] << repo.nwo
      payload[:repo_id] << repo.id
    end
    payload
  end

  def force_failed_import!
    failed_import_state = self.class.workflow_state(:failed_import)
    if persisted?
      update_column(:state, failed_import_state.value)
    else
      state = :failed_import
    end
  end

  def clean_up
    DeleteDependentRecordsJob.set(wait_until: 6.hours.from_now).perform_later(self.class.name, guid, :migratable_resources)
  end

  def exported(*args, **kwargs)
    return if owner.organization?
    return unless GitHub.download_everything_button_enabled?

    url = GitHub.url + url_with_token
    AccountMailer.download_everything(owner, url).deliver_later
  end

  def self.state_value(name)
    workflow_spec.states[name.to_sym].value
  end

  DISABLE_EXPORT_FOR_ACTOR_KEY = "disable-export-for-actor"

  def self.disable_export_for_actor_key(actor)
    "#{DISABLE_EXPORT_FOR_ACTOR_KEY}-#{actor.id}"
  end

  def self.disable_export_for_actor(actor)
    GitHub::Migrator::KV.store.set(disable_export_for_actor_key(actor), "true", expires: 1.day.from_now)
  end

  def self.enable_export_for_actor(actor)
    GitHub::Migrator::KV.store.del(disable_export_for_actor_key(actor))
  end

  def self.export_disabled_for_actor?(actor)
    GitHub::Migrator::KV.store.exists(disable_export_for_actor_key(actor)).value { false }
  end

  def url_with_token
    token = owner.signed_auth_token \
          scope:   TOKEN_SCOPE,
          expires: created_at + 7.days,
          data:    { migration_id: id }

    settings_user_migration_download_path(token: token)
  end

  def send_user_migration_email
    url = GitHub.url + url_with_token
    AccountMailer.download_everything(owner, url).deliver_later
  end

  def self.token_to_url(token_string, current_user)
    token = User.verify_signed_auth_token \
                token: token_string,
                scope: TOKEN_SCOPE
    return unless token.valid?

    migration = Migration.find_by_id(token.data["migration_id"])
    return unless migration && migration.owner == current_user
    return unless migration.file

    migration.file.download_url(actor: current_user)
  end

  def record_timing(action, &block)
    MigrationTiming.record(self, action, &block)
  end

  def safely_change_migration_state!(event)
    retries_remaining = MAX_RETRIES
    begin
      self.reload
      self.send(event)
    rescue Workflow::NoTransitionAllowed => error
      if retries_remaining.zero?
        tags = ["migrator_pid:#{process_id}", "guid:#{self.guid}",  "state:#{self.state}"]
        GitHub.dogstats.increment("migrator.import.no_transition_allowed", tags: tags)
        GitHub.logger.error(
          "Exhausted retries for NoTransitionAllowed",
          {
            :exception => error,
            "code.function" => "safely_change_migration_state",
            "code.namespace" => self.class.name,
            "gh.migration_tools.migration.type" => "repo",
            "gh.migration_tools.migration.guid" => self.guid,
            "gh.migration_tools.migration.state" => self.current_state.name.to_s,
          }
        )
        raise
      else
        retries_remaining -= 1
        sleep retry_sleep_time(retries_remaining) unless Rails.env.test?
        retry
      end
    end
  end

  def retry_sleep_time(retries_remaining)
    2**(MAX_RETRIES - retries_remaining)
  end

  def process_id
    $$
  end
end
