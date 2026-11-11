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

  validates :target_id, presence: true, numericality: { greater_than: 0 }
  validates :target_type, inclusion: VALID_TARGET_TYPES

  delegate :single_file_name,
    :single_file_paths,
    :multiple_single_files?,
    to: :version

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
      payload[target.event_prefix] = target if target
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

  def instrument_extend_expires_at(_token_last_eight = nil)
    instrument :extend_expires_at, { expires_at: expires_at }
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
    DestroyAuthenticationTokensJob.perform_later(self.id, T.must(self.class.name))
  end
end
