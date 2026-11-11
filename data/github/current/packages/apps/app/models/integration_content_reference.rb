# typed: true
# frozen_string_literal: true

# DEPRECATED, see: https://github.com/github/platform-ux/issues/1050
# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class IntegrationContentReference < ApplicationRecord::Domain::Integrations
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  include GitHub::Validations
  belongs_to :integration_version

  enum :reference_type, ["domain"]

  validates_presence_of :value
  validates_presence_of :reference_type
  validates_presence_of :integration_version
  validates :value, unicode3: true
  validates :value, uniqueness: { scope: :integration_version, case_sensitive: false }, if: -> { T.bind(self, IntegrationContentReference).errors[:value].blank? }
  validate :valid_domain, if: -> { T.bind(self, IntegrationContentReference).domain? }

  BANNED_DOMAINS = [
    "github.com",
    "githubusercontent.com",
    "githubassets.com",
    "git.io",
    "octocaptcha.com",
  ]

  def self.integrations_listening_for(repository:, url:)
    # We're making the assumption right now that all content references are URLs
    host = ContentReference::Uri.host(url)

    # Get the resources that the integrations needs to have access to see the event type
    resources_for_event = Integration::Events.repository_resources_for_event("content_reference")

    # Get all integration installation ids on the repo with the required permissions
    installation_ids = IntegrationInstallation.ids_with_resources_on(
      subject_class: repository.class,
      subject_id: repository.id,
      subject_owner_id: repository.owner_id,
      resources: resources_for_event)
    return Integration.none if installation_ids.empty?

    # Filter down to integration installation ids that are subscribed to the given event
    installation_ids = HookEventSubscription.with_name_and_subscriber("content_reference", "IntegrationInstallation", installation_ids).pluck(:subscriber_id)
    return Integration.none if installation_ids.empty?

    integration_ids = IntegrationInstallation.
      joins("INNER JOIN integration_versions ON integration_installations.integration_version_number = integration_versions.number AND integration_installations.integration_id = integration_versions.integration_id").
      joins("INNER JOIN integration_content_references ON integration_versions.id = integration_content_references.integration_version_id").
      where("integration_content_references.value = ? OR ? LIKE CONCAT('%.', integration_content_references.value)", host, host).
      where(id: installation_ids).distinct.pluck(:integration_id)
    return Integration.none if integration_ids.empty?

    Integration.where(id: integration_ids)
  end

  def valid_domain
    unless (
      PublicSuffix.valid?(value, default_rule: nil, ignore_private: true) &&
      BANNED_DOMAINS.map { |banned_domain| value.end_with?(banned_domain) }.none?
    )
      errors.add(:value, "is not a valid domain.")
    end
  end

  def host_matches(url)
    host = ContentReference::Uri.host(url)
    host == self.value || host.end_with?(".#{self.value}")
  end

  def matches(reference)
    self.domain? && host_matches(reference)
  end
end
