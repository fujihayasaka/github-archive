# typed: true
# frozen_string_literal: true

class ScopedIntegrationInstallation < ApplicationRecord::Domain::IntegrationsCollab
  DEFAULT_PER_REPO_RATE_LIMIT = 1_000 # This can be overridden on a per-apps basis in the Internal Registry

  include Ability::Actor
  include AuthenticationTokenable
  include Instrumentation::Model
  include IntegrationInstallable
  include ScopedIntegrationInstallable
  include GitHub::Memoizer
  include ProgrammaticActor::AuthorizationDetailsGrantable

  # rubocop:todo Rails/InverseOf
  belongs_to :parent,
    class_name: "IntegrationInstallation",
    foreign_key: :integration_installation_id,
    optional: false
  # rubocop:enable Rails/InverseOf

  after_commit :destroy_associated_tokens, on: :destroy

  has_many :permission_records, as: :actor, class_name: "Permission"
  destroy_dependents_in_background :permission_records

  has_one :integration, through: :parent

  has_one :version,
    class_name: "IntegrationVersion",
    through: :parent

  delegate :integrator_suspended?,
           :integrator_suspended_at,
           :suspended?,
           :target_id,
           :target_type,
           :user_suspended?,
           :user_suspended_at,
           to: :parent

  delegate :single_file_name,
    :single_file_paths,
    :multiple_single_files?,
    to: :version

  before_update :validate_authorization_details

  validates_presence_of :integration_installation_id

  after_commit :upsert_record_to_lodge, on: [:create, :update]
  after_commit :destroy_record_in_lodge, on: [:destroy]

  attribute :expires_at, :utc_timestamp

  # Public: The target for the parent.
  #
  # Returns a Promise.
  def async_target
    async_parent.then do |parent|
      T.must(parent).async_target
    end
  end

  # Public: The parent Integration's id.
  #
  # Returns an Integer.
  def integration_id
    T.must(integration).id
  end

  # Public: The target for the parent.
  #
  # Returns a User/Organization/Business.
  def target
    async_target.sync
  end

  # Returns a human readable string for use in audit logs.
  def name
    "scoped_integration_installation-#{id}"
  end

  def event_context(prefix: event_prefix)
    {
      prefix => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def event_payload
    {}.tap do |payload|
      payload[event_prefix]                     = self
      payload[:parent_integration_installation] = parent
      payload[:integration]                     = integration
      payload[:repository_selection]            = repository_selection
      if !installed_on_all_repositories?
        payload[:repository_ids] = repository_ids
      end
      payload[target.event_prefix]              = target if target
      payload[:permissions]                     = permissions
      payload[:created_at]                      = created_at
    end
  end

  # Public: returns the API rate limit for this scoped installation. Considers
  # whether the App has the capability to have per-repo rate limits, otherwise
  # delegates to the parent installation.
  #
  # Returns an Integer.
  def rate_limit
    return @rate_limit if defined?(@rate_limit)
    @rate_limit = per_repo_rate_limit? ? per_repo_rate_limit : T.must(parent).rate_limit
  end

  def per_repo_rate_limit?
    Apps::Privileged.capable?(:per_repo_rate_limit, app: self.integration) &&
      repository_ids.count == 1
  end

  # Can the GH App be a granted an Ability or UserRole over a given subject?
  # A GH App can only be granted a subset of the permissions that the owner user is allowed to perform over the subject.
  # So there is no need for additional guards when granting permissions.
  def can_be_granted_permission_over!(subject, action); end

  def instrument_creation
    instrumenter = Apps::InstallationInstrumenter.new(self)
    instrumenter.instrument_scoped_creation(event_payload)
  end

  private

  def could_dual_write?
    !(GitHub.enterprise? || GitHub.multi_tenant_enterprise?)
  end

  def destroy_record_in_lodge
    return unless could_dual_write?

    begin
      ApplicationRecord::Domain::IntegrationsLodge.connection.delete(Arel.sql(<<-SQL, id: self.id, updated_at: self.attributes_for_database["updated_at"]))
        DELETE FROM scoped_integration_installations WHERE id = :id AND updated_at = :updated_at
      SQL
      GitHub.dogstats.increment("scoped_installations.destroy_record_in_lodge", tags: ["table:scoped_integration_installations", "result:success"])
    rescue ActiveRecord::ActiveRecordError => e
      GitHub.dogstats.increment("scoped_installations.destroy_record_in_lodge", tags: ["table:scoped_integration_installations", "result:failure"])
      Failbot.report!(e) # report but don't raise
    end
  end

  def instrument_extend_expires_at
    token = ServerToServerTokens.domain.first_by_authenticatable_id(self.id)

    options = {}.tap do |opts|
      opts[:expires_at] = expires_at
      opts[:token_last_eight] = token.token_last_eight if !token.nil? # ScopedIntegrationInstallations should only ever have one token
    end

    instrument :extend_expires_at, options
  end

  def per_repo_rate_limit
    per_repo_rate_limit = Apps::Privileged.property(
      :hourly_per_repo_rate_limit, app: self.integration,
    ) || DEFAULT_PER_REPO_RATE_LIMIT

    return per_repo_rate_limit unless self.integration == GitHub.launch_github_app

    # This is a short-term exception to unblock a single repository
    # that is rate-limited in GitHub Actions
    repo_actor = RepositoryFlipperActor.new(repository_ids.first)
    return per_repo_rate_limit unless repo_actor.feature_flag_enabled?(:override_actions_per_repo_rate_limit, default: false)

    T.must(parent).rate_limit
  end

  def should_dual_write?
    could_dual_write? && parent&.feature_flag_enabled?(:dual_write_scoped_integration_installations_to_lodge, default: false)
  end

  def upsert_record_to_lodge
    return unless should_dual_write?

    positional_binds = self.attributes_for_database.symbolize_keys

    sql = Arel.sql(<<-SQL, **positional_binds)
      INSERT INTO scoped_integration_installations (
        id, integration_installation_id, created_at,
        updated_at, expires_at, authorization_details
      ) VALUES (
        :id, :integration_installation_id, :created_at,
        :updated_at, :expires_at, :authorization_details
      ) ON DUPLICATE KEY UPDATE
        integration_installation_id = IF(updated_at < VALUES(updated_at), VALUES(integration_installation_id), integration_installation_id),
        created_at = IF(updated_at < VALUES(updated_at), VALUES(created_at), created_at),
        updated_at = IF(updated_at < VALUES(updated_at), VALUES(updated_at), updated_at),
        expires_at = IF(updated_at < VALUES(updated_at), VALUES(expires_at), expires_at),
        authorization_details = IF(updated_at < VALUES(updated_at), VALUES(authorization_details), authorization_details)
    SQL

    begin
      ApplicationRecord::Lodge.connection.insert(sql)
      GitHub.dogstats.increment("scoped_installations.upsert_record_in_lodge", tags: ["table:scoped_integration_installations", "result:success"])
    rescue ActiveRecord::ActiveRecordError => e
      GitHub.dogstats.increment("scoped_installations.upsert_record_in_lodge", tags: ["table:scoped_integration_installations", "result:failure"])
      Failbot.report!(e) # report but don't raise
    end
  end

  def validate_authorization_details
    return unless authorization_details_applicable?

    begin
      self.authorization_details_struct.validate!; true
    rescue JSON::Schema::ValidationError, KeyError => e
      self.errors.add(:authorization_details, e)
    end
  end

  def destroy_associated_tokens
    total_records = ServerToServerTokens.domain.count_by_authenticatable_id(self.id)
    DestroyAuthenticationTokensJob.perform_later(self.id, self.class.name) if total_records.nil? || total_records.positive?
  end
end
