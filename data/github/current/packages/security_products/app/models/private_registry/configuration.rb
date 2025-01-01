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
  validates :url, presence: true, format: {
    with: URI::DEFAULT_PARSER.make_regexp,
    message: "must be valid"
  }, length: { maximum: 8000 }

  enum :registry_type, {
    maven_repository: 0,
    nuget_feed: 1,
    goproxy_server: 2,
    npm_registry: 3,
    rubygems_server: 4,
    cargo_registry: 5,
    composer_repository: 6,
    docker_registry: 7,
    git_source: 8,
    helm_registry: 9,
    # hex_organization: 10,
    # hex_repository: 11,
    pub_repository: 12,
    python_index: 13,
    terraform_registry: 14,
  }, validate: true

  HUMAN_READABLE_REGISTRY_TYPES = {
    maven_repository: "Maven Repository",
    nuget_feed: "NuGet Feed",
    goproxy_server: "GOPROXY server",
    npm_registry: "NPM Registry",
    rubygems_server: "RubyGems Server",
    cargo_registry: "Cargo Registry",
    composer_repository: "Composer Repository",
    docker_registry: "Docker Registry",
    git_source: "Git Source",
    helm_registry: "Helm Registry",
    # hex_organization: "Hex Organization",
    # hex_repository: "Hex Repository",
    pub_repository: "Pub Repository",
    python_index: "Python Index",
    terraform_registry: "Terraform Registry",
  }.freeze

  HUMANIZED_ATTRIBUTES = { url: "URL" }

  scope :for_organization, -> (org) { where(owner_type: "Organization", owner_id: org.id).order(:id) if org.present? }

  def self.human_attribute_name(attr, options = {})
    HUMANIZED_ATTRIBUTES[attr.to_sym] || super
  end

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

  def self.human_readable_registry_types(org)
    types = {
      maven_repository: HUMAN_READABLE_REGISTRY_TYPES[:maven_repository],
      nuget_feed: HUMAN_READABLE_REGISTRY_TYPES[:nuget_feed],
      goproxy_server: HUMAN_READABLE_REGISTRY_TYPES[:goproxy_server]
    }

    types[:npm_registry] = HUMAN_READABLE_REGISTRY_TYPES[:npm_registry]
    types[:rubygems_server] = HUMAN_READABLE_REGISTRY_TYPES[:rubygems_server]
    types[:cargo_registry] = HUMAN_READABLE_REGISTRY_TYPES[:cargo_registry]
    types[:composer_repository] = HUMAN_READABLE_REGISTRY_TYPES[:composer_repository]
    types[:docker_registry] = HUMAN_READABLE_REGISTRY_TYPES[:docker_registry]
    types[:git_source] = HUMAN_READABLE_REGISTRY_TYPES[:git_source]
    types[:helm_registry] = HUMAN_READABLE_REGISTRY_TYPES[:helm_registry]
    # types[:hex_organization] = HUMAN_READABLE_REGISTRY_TYPES[:hex_organization]
    # types[:hex_repository] = HUMAN_READABLE_REGISTRY_TYPES[:hex_repository]
    types[:pub_repository] = HUMAN_READABLE_REGISTRY_TYPES[:pub_repository]
    types[:python_index] = HUMAN_READABLE_REGISTRY_TYPES[:python_index]
    types[:terraform_registry] = HUMAN_READABLE_REGISTRY_TYPES[:terraform_registry]

    types
  end

  private

  def datadog_tags
    [
      "owner_type:#{owner_type}",
      "registry_type:#{registry_type}",
    ]
  end
end
