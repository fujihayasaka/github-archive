# typed: true
# frozen_string_literal: true

class PrivateRegistry::Configuration < ApplicationRecord::Notify
  self.table_name = "private_registry_configurations"
  belongs_to :owner, polymorphic: true

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_delete, on: :destroy

  validates :owner_id, presence: true
  validates :owner_type, presence: true, inclusion: { in: %w(Organization) }

  validates :registry_type, presence: true
  validates :secret_name, presence: true
  validates :url, presence: true

  enum :registry_type, {
    maven_repository: 0,
    nuget_feed: 1,
  }, validate: true

  HUMAN_READABLE_REGISTRY_TYPES = {
    maven_repository: "Maven Repository",
    nuget_feed: "NuGet Feed"
  }

  scope :for_organization, -> (org) { where(owner_type: "Organization", owner_id: org.id) if org.present? }

  def authenticates_with_username_and_password?
    case registry_type
    when "maven_repository"
      true
    else
      false
    end
  end

  def instrument_create
    GitHub.dogstats.increment("#{event_prefix}.create", tags: datadog_tags)
  end

  def instrument_update
    tags = datadog_tags

    updated_attribute_names = previous_changes.keys & %w(url username)
    tags << "url_changed:#{updated_attribute_names.include?("url")}"
    tags << "username_changed:#{updated_attribute_names.include?("username")}"

    GitHub.dogstats.increment("#{event_prefix}.update", tags: tags)
  end

  def instrument_delete
    GitHub.dogstats.increment("#{event_prefix}.delete", tags: datadog_tags)
  end

  def event_prefix
    "private_registry_configuration"
  end

  private

  def datadog_tags
    [
      "owner_type:#{owner_type}",
      "registry_type:#{registry_type}",
    ]
  end
end
