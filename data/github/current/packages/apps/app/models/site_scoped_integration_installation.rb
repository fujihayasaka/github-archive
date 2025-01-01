# typed: true
# frozen_string_literal: true

class SiteScopedIntegrationInstallation < ApplicationRecord::Domain::IntegrationsCollab

  VALID_TARGET_TYPES = %w(User Business).freeze

  include Ability::Actor
  include AuthenticationTokenable
  include Instrumentation::Model
  include IntegrationInstallable
  include ScopedIntegrationInstallable
  include ProgrammaticActor::AuthorizationDetailsGrantable

  belongs_to :integration, optional: false
  belongs_to :target, polymorphic: true

  after_commit :destroy_associated_tokens, on: :destroy

  has_many :permission_records, as: :actor, class_name: "Permission"
  destroy_dependents_in_background :permission_records

  has_many :codespaces_site_scoped_integration_installations
  destroy_dependents_in_background :codespaces_site_scoped_integration_installations

  has_one :latest_version,
    class_name: "IntegrationVersion",
    through: :integration

  def version
    latest_version
  end

  def version=(version)
    self.latest_version = version
  end

  validates_presence_of :integration

  validates_presence_of :target
  validates :target_type, inclusion: VALID_TARGET_TYPES

  delegate :single_file_name,
    :single_file_paths,
    :multiple_single_files?,
    to: :version

  after_commit :upsert_record_to_lodge, on: [:create, :update]
  after_commit :destroy_record_in_lodge, on: [:destroy]

  attribute :expires_at, :utc_timestamp

  # Public: The rate limit for this installation.
  #         SiteScopedIntegrationInstallations default to the global API
  #         rate limit, but this can be overriden by configuring the
  #         `site_scoped_rate_limit` property on the internal app.
  #
  # Returns an Integer.
  def rate_limit
    return self[:rate_limit] if self[:rate_limit].present?

    Apps::Privileged.property(:site_scoped_rate_limit, app: integration)
  end

  # Returns a human readable string for use in audit logs.
  def name
    "site_scoped_integration_installation-#{id}"
  end

  def event_context(prefix: event_prefix)
    {
      prefix => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def event_payload
    {}.tap do |payload|
      payload[event_prefix]        = self
      payload[:integration]        = integration
      payload[target.event_prefix] = target
      payload[:permissions]        = permissions
    end
  end

  def suspended?
    false
  end

  def user_suspended?
    false
  end

  def integrator_suspended?
    false
  end

  def codespace_ids
    if !self.fallback_to_permissions?
      details = self.authorization_details_struct
      details.granted_subject_ids_for(ScopedInstallations::AuthorizationDetails::ResourceType::Codespace)
    else
      Permission.where(
        actor_id: self.ability_id,
        actor_type: self.ability_type,
        action: :read,
        subject_type: "Codespace/codespace_metadata"
      ).pluck(:subject_id)
    end
  end

  def instrument_creation
    instrument :create
  end

  def per_repo_rate_limit?
    return false unless Apps::Privileged.capable?(:per_repo_rate_limit, app: integration)
    return false if installed_on_all_repositories?
    permissions_repositories_count(limit: 2) == 1
  end

  def repo_owner_rate_limit?
    return false unless Apps::Privileged.capable?(:repo_owner_rate_limit, app: integration)
    return true if installed_on_all_repositories?
    permissions_repositories_count(limit: 2) > 1
  end

  private

  def could_dual_write?
    !(GitHub.enterprise? || GitHub.multi_tenant_enterprise?)
  end

  def destroy_record_in_lodge
    return unless could_dual_write?

    begin
      ApplicationRecord::Domain::IntegrationsLodge.connection.delete(Arel.sql(<<-SQL, id: self.id, updated_at: self.attributes_for_database["updated_at"]))
        DELETE FROM site_scoped_integration_installations WHERE id = :id AND updated_at = :updated_at
      SQL
      GitHub.dogstats.increment("scoped_installations.destroy_record_in_lodge", tags: ["table:site_scoped_integration_installations", "result:success"])
    rescue ActiveRecord::ActiveRecordError => e
      GitHub.dogstats.increment("scoped_installations.destroy_record_in_lodge", tags: ["table:site_scoped_integration_installations", "result:failure"])
      Failbot.report!(e) # report but don't raise
    end
  end

  def instrument_extend_expires_at
    instrument :extend_expires_at, { expires_at: expires_at }
  end

  def should_dual_write?
    could_dual_write? && integration&.feature_enabled?(:dual_write_site_scoped_integration_installations_to_lodge)
  end

  def upsert_record_to_lodge
    return unless should_dual_write?

    positional_binds = self.attributes_for_database.symbolize_keys

    sql = Arel.sql(<<-SQL, **positional_binds)
      INSERT INTO site_scoped_integration_installations (
        id, integration_id, target_id, target_type,
        created_at, updated_at, expires_at, rate_limit,
        authorization_details
      ) VALUES (
        :id, :integration_id, :target_id, :target_type,
        :created_at, :updated_at, :expires_at, :rate_limit,
        :authorization_details
      ) ON DUPLICATE KEY UPDATE
        integration_id = IF(updated_at < VALUES(updated_at), VALUES(integration_id), integration_id),
        target_id = IF(updated_at < VALUES(updated_at), VALUES(target_id), target_id),
        target_type = IF(updated_at < VALUES(updated_at), VALUES(target_type), target_type),
        created_at = IF(updated_at < VALUES(updated_at), VALUES(created_at), created_at),
        updated_at = IF(updated_at < VALUES(updated_at), VALUES(updated_at), updated_at),
        expires_at = IF(updated_at < VALUES(updated_at), VALUES(expires_at), expires_at),
        rate_limit = IF(updated_at < VALUES(updated_at), VALUES(rate_limit), rate_limit),
        authorization_details = IF(updated_at < VALUES(updated_at), VALUES(authorization_details), authorization_details)
    SQL

    begin
      ApplicationRecord::Lodge.connection.insert(sql)
      GitHub.dogstats.increment("scoped_installations.upsert_record_in_lodge", tags: ["table:site_scoped_integration_installations", "result:success"])
    rescue ActiveRecord::ActiveRecordError => e
      GitHub.dogstats.increment("scoped_installations.upsert_record_in_lodge", tags: ["table:site_scoped_integration_installations", "result:failure"])
      Failbot.report!(e) # report but don't raise
    end
  end

  def permissions_repositories_count(limit:)
    pseudo_subject = Repository.new.resources.metadata

    if fallback_to_permissions?
      Permission
        .select(:subject_id)
        .where(
          actor_id: ability_id,
          actor_type: ability_type,
          subject_type: pseudo_subject.ability_type,
        )
        .limit(limit)
        # Explicitly load the records to avoid the MySQL count query.
        # https://github.com/github/github/pull/313121/files#r1492707849
        .to_a
        .size
    else
      self.authorization_details_struct.granted_subject_ids_for(
        ScopedInstallations::AuthorizationDetails::ResourceType::Repository,
        pseudo_subject.name
      ).first(limit).count
    end
  end

  def destroy_associated_tokens
    total_records = ServerToServerTokens.domain.count_by_authenticatable_id(self.id)
    DestroyAuthenticationTokensJob.perform_later(self.id, self.class.name) if total_records.nil? || total_records.positive?
  end
end
