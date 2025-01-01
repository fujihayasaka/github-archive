# typed: true
# frozen_string_literal: true

class PrivateRegistry::Secret
  include ActiveModel::Model
  extend T::Sig

  class Error < StandardError; end
  class CreationError < PrivateRegistry::Secret::Error; end
  class ValidationError < PrivateRegistry::Secret::Error; end

  delegate :secret_name, :secret_name=, :owner, :owner=, :owner_type, :owner_type=, :registry_type, :registry_type=, :url, :url=, to: :configuration
  alias_method :name, :secret_name
  alias_method :name=, :secret_name=

  attr_accessor :credential
  attr_reader :encrypted_value
  attr_writer :visibility, :selected_repository_ids

  sig { returns(PrivateRegistry::Configuration) }
  attr_accessor :configuration

  validate :validate_secret

  def self.build(owner:, owner_type:, registry_type:, url:, name:, encrypted_value: nil, visibility: nil, selected_repository_ids: [])
    # Don't create a record yet - lest everything else is invalid.
    config = PrivateRegistry::Configuration.find_or_initialize_by(owner:, owner_type:, registry_type:, url:, secret_name: name)

    new(
      configuration: config,
      encrypted_value:,
      visibility:,
      selected_repository_ids:,
    )
  end

  # Get a list of secrets for an organization and registry type.
  def self.for_organization(org:)
    PrivateRegistry::Configuration.for_organization(org).map(&:to_secret)
  end

  # Get the first matching secret
  sig { params(org: Organization, url: String).returns(T.nilable(PrivateRegistry::Secret)) }
  def self.fetch(org:, url:)
    PrivateRegistry::Configuration.for_organization(org).find_by(url: url)&.to_secret
  end

  # Send encoded value to Credz
  def save
    return false unless valid?(:new)
    save!
  rescue PrivateRegistry::Secret::Error, ArgumentError, ActiveModel::Error, ActiveRecord::ActiveRecordError => e
    false
  end

  # Send encoded value to Credz and save configuration if it succeeds.
  def save!
    raise PrivateRegistry::Secret::ValidationError.new("Validation failed") unless valid?(:new)

    result = Secrets.create(
      app: app,
      owner: owner,
      actor: owner,
      name: name,
      value: encoded_value,
      visibility: visibility,
      selected_repositories: selected_repository_ids || []
    )

    if result&.stored
      begin
        configuration.save!
      rescue ::ActiveModel::Error, ::ActiveRecord::ActiveRecordError => e
        Secrets.delete(name: name, owner: owner, actor: owner, app: app)
        raise e
      end
    else
      raise PrivateRegistry::Secret::CreationError.new("Could not persist secret in Credz: #{result}")
    end
  end

  def encoded_value
    return @encoded_value if defined?(@encoded_value)
    return @encoded_value = encode_value(encrypted_value) if encrypted_value.present?

    # Try populating it from Credz.
    populate_from_credz
    @encoded_value
  end

  def encrypted_value=(value)
    @encrypted_value = value

    # We want to update `@encoded_value` any time `@encrypted_value` is updated.
    @encoded_value = encode_value(encrypted_value) if encrypted_value.present?
  end

  sig { returns(T.nilable(Symbol)) }
  def visibility
    populate_from_credz if @visibility.blank?
    populate_from_credz unless defined?(@visibility)

    @visibility
  end

  sig { returns(T.nilable(T::Array[Integer])) }
  def selected_repository_ids
    populate_from_credz if @selected_repository_ids.blank?
    populate_from_credz unless defined?(@selected_repository_ids)

    @selected_repository_ids
  end

  private

  def validate_secret
    validation = GitHub::KredzClient::Credz.validate_secret(name, encrypted_value)
    errors.add(:secret_name, :invalid, message: validation.error) unless validation.succeeded?

    configuration.validate
    errors.merge!(configuration.errors)
  end

  sig { returns(DietEarthsmoke::Key) }
  def encryption_key
    @encryption_key ||= DietEarthsmoke::Key.new(Platform::EncryptionKeys::PRIVATE_REGISTRY_SECRETS)
  end

  def app
    @app ||= ::Apps::Internal.integration(:private_registry_secrets)
  end

  def encode_value(value)
    encryption_key.seal(value, scope: owner.next_global_id)
  end

  def populate_from_credz
    begin
      result = Secrets.fetch(
        name: name,
        app: app,
        owner: owner,
        actor: owner,
        include_value: true,
      )
    rescue Secrets::Error
      return nil
    end

    credential = result&.credential

    if credential.present?
      @encoded_value = credential.value
      @visibility = credential.visibility

      selected_repository_node_ids = credential.selected_repositories.map(&:global_id).to_set
      @selected_repository_ids = selected_repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i }
    end

    credential
  end
end
