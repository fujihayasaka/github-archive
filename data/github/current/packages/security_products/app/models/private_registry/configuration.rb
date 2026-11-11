# typed: true
# frozen_string_literal: true

class PrivateRegistry::Configuration < ApplicationRecord::Notify
  self.table_name = "private_registry_configurations"
  belongs_to :owner, polymorphic: true

  before_validation :set_secret_name!, on: :create
  before_validation :clear_unused_config_fields, if: :auth_type_changing_on_persisted_record?

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

  enum :auth_type, {
    token: 0,
    username_password: 1,
    oidc_azure: 2,
    oidc_aws: 3,
    oidc_jfrog: 4,
  }, validate: true

  OIDC_CONFIG_FIELDS = {
    "oidc_azure" => %w[tenant_id client_id],
    "oidc_aws"   => %w[aws_region account_id role_name domain domain_owner audience],
    "oidc_jfrog" => %w[jfrog_oidc_provider_name audience identity_mapping_name],
  }.freeze

  OIDC_REQUIRED_FIELDS = {
    "oidc_azure" => %w[tenant_id client_id],
    "oidc_aws"   => %w[aws_region account_id role_name domain domain_owner],
    "oidc_jfrog" => %w[jfrog_oidc_provider_name],
  }.freeze

  OIDC_CONFIG_FIELDS.values.flatten.uniq.each do |field|
    define_method(field) do
      T.bind(self, PrivateRegistry::Configuration)
      (self.oidc_config || {})[field]
    end

    define_method("#{field}=") do |value|
      T.bind(self, PrivateRegistry::Configuration)
      self.oidc_config = (self.oidc_config || {}).merge(field => value)
    end
  end

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

  SequenceContext = Struct.new(:base_name, :owner_id) do
    include Sequence::Context
    def sequence_context_type = "PrivateRegistry::Configuration::#{base_name}"
    def sequence_context_id  = owner_id
  end

  scope :for_organization, -> (org) { where(owner_type: "Organization", owner_id: org.id).order(:id) if org.present? }

  validate :validate_oidc_required_fields, if: :oidc?
  validate :validate_oidc_config_keys, if: :oidc?

  def self.human_attribute_name(attr, options = {})
    HUMANIZED_ATTRIBUTES[attr.to_sym] || super
  end

  def oidc?
    OIDC_CONFIG_FIELDS.key?(auth_type)
  end

  def authenticates_with_username_and_password?
    return false if oidc?

    registry_type == "maven_repository"
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

  def set_secret_name!
    return if secret_name.present?
    return if registry_type.blank?

    base = compute_base_name
    ctx = SequenceContext.new(base, owner_id)
    unless Sequence.exists?(ctx)
      max_suffix = compute_max_existing_suffix(base)
      Sequence.create(ctx, max_suffix)
    end
    n = Sequence.next(ctx)
    self.secret_name = n == 1 ? base : "#{base}_#{n}"
  end

  def compute_base_name
    if oidc?
      "#{registry_type.upcase}_#{auth_type.to_s.upcase}"
    else
      "#{registry_type.upcase}_SECRET"
    end
  end

  def compute_max_existing_suffix(base)
    existing = self.class.where(owner_type: owner_type, owner_id: owner_id)
      .where("secret_name LIKE ?", "#{self.class.sanitize_sql_like(base)}%")
      .pluck(:secret_name)

    suffixes = existing.filter_map do |name|
      if name == base
        1
      elsif name.start_with?("#{base}_")
        suffix = name.delete_prefix("#{base}_")
        suffix.match?(/\A\d+\z/) ? suffix.to_i : nil
      end
    end
    suffixes.max || 0
  end

  def datadog_tags
    [
      "owner_type:#{owner_type}",
      "registry_type:#{registry_type}",
      "auth_type:#{auth_type}",
    ]
  end

  def validate_oidc_required_fields
    OIDC_REQUIRED_FIELDS.fetch(auth_type, []).each do |field|
      errors.add(field.to_sym, :blank) if (oidc_config || {})[field].blank?
    end
  end

  def validate_oidc_config_keys
    return if oidc_config.blank?

    valid_fields = OIDC_CONFIG_FIELDS.fetch(auth_type, [])
    invalid_keys = oidc_config.keys - valid_fields
    invalid_keys.each do |key|
      errors.add(:oidc_config, "contains invalid field '#{key}' for auth_type '#{auth_type}'")
    end
  end

  def clear_unused_config_fields
    return if oidc_config.blank?

    valid_fields = OIDC_CONFIG_FIELDS[auth_type]
    if valid_fields.nil?
      self.oidc_config = nil
    else
      cleaned = oidc_config.slice(*valid_fields)
      self.oidc_config = cleaned.presence
    end
  end

  def auth_type_changing_on_persisted_record?
    persisted? && will_save_change_to_auth_type?
  end
end
