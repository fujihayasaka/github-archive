# typed: true
# frozen_string_literal: true

require "oauth_util"

class IntegrationManifest < ApplicationRecord::Collab
  belongs_to :owner, class_name: "User"
  belongs_to :creator, class_name: "User"

  validate :validate_data_conforms_to_json_schema
  validate :validate_redirect_url

  validate :validate_permission_actions
  validate :validate_integration

  after_validation :prefill_name

  before_create :generate_code

  def data
    JSON.parse(self[:data])
  end

  def generate_code
    self.code = SecureRandom.hex(20)
  end

  def create_integration!
    integration = T.cast(T.must(owner).integrations.build(build_integration_params), Integration)

    # Hooks are now optional.
    if integration.hook
      # Make the webhook active by default
      unless build_integration_params["hook_attributes"].key?("active")
        T.must(integration.hook).active = true
      end

      T.must(integration.hook).generate_secret
    end

    integration.save!

    self.destroy

    key = integration.generate_key(creator: creator)
    pem = key.private_key.to_pem
    secret = integration.generate_client_secret(creator: creator).secret
    [integration, pem, secret]
  end

  def generate_kv_key
    SecureRandom.hex(20)
  end

  def target_for_conditional_access
    owner
  end

  def async_target_for_conditional_access
    async_owner
  end

  # Meant to duck type Ability::Subject#readable_by?
  def readable_by?(_)
    true
  end

  private

  # Add JSON schema errors to the model's validation errors.
  def validate_data_conforms_to_json_schema
    begin
      validation = Api::V3SchemaCollection.validate(data: data, resource: "integration", rel: "build")
    rescue JSON::ParserError, TypeError
      errors.add(:base, "The manifest is not valid JSON")
    else
      validation.error_messages.each { |error| errors.add(:base, error) }
    end
  end

  def validate_redirect_url
    return unless self.errors.empty?

    strict_options = {
      blocked_query_keys: OauthUtil::RESERVED_REDIRECT_URI_QUERY_KEYS,
      allow_fragment: false,
    }
    unless IntegrationUrl.valid_callback_url?(data["redirect_url"], strict_options)
      errors.add(:base, "redirect_url must be a valid URL")
    end
  end

  def prefill_name
    return unless self.errors.empty?
    return if name.present?
    if data["name"].present?
      self.name = data["name"]
    end
  end

  def build_integration_params
    @build_integration_params ||= begin
      integration_params = data
      content_references = integration_params.delete("content_references")
      if content_references != nil
        # Create a hash from the content_references array,
        # where the keys are the value (e.g. domain) and the values are the content_reference type
        # e.g { "example.com" => "domain" }
        integration_params["default_content_references"] = content_references.reduce({}) { |h, v| h[v["value"]] = v["type"]; h }
      end

      if integration_params.key?("callback_url") || integration_params.key?("callback_urls")
        callback_urls = if integration_params.key?("callback_url")
          # Delete in case someone tries to set both
          integration_params.delete("callback_urls")

          [integration_params.delete("callback_url")]
        elsif integration_params.key?("callback_urls")
          # Delete in case someone tries to set both
          integration_params.delete("callback_url")

          Array(integration_params.delete("callback_urls"))
        end

        integration_params["application_callback_urls_attributes"] = \
          T.must(callback_urls).map { |url| { url: url } }
      end

      events = integration_params.delete("default_events")
      if events
        integrator_events, default_events = events.partition { |e| Integration::Events::INTEGRATOR_EVENTS.include?(e) }
        integration_params["default_events"] = default_events
        integration_params["integrator_events"] = integrator_events
      end

      integration_params = IntegrationsControllerMethods.handle_deprecated_integrations_public_field(integration_params)

      integration_params.delete("redirect_url")
      integration_params.delete("version")
      integration_params.merge("name" => name)
    end
  end

  def should_validate_name?
    self.name.present?
  end

  def should_add_error?(attribute)
    if [:name, :bot].include?(attribute)
      return should_validate_name?
    end

    true
  end

  def validate_integration
    return unless self.errors.empty?
    return unless owner.present?

    integration = T.cast(T.must(owner).integrations.build(build_integration_params), Integration)

    unless integration.valid?
      integration.errors.each do |error|
        attribute = error.attribute

        if attribute == :name
          errors.add(:name, error.message) if should_add_error?(attribute)
        else
          errors.add(:base, integration.errors.full_message(attribute, error.message)) if should_add_error?(attribute)
        end
      end
    end
  end

  def validate_permission_actions
    return unless self.errors.empty?

    permissions = build_integration_params["default_permissions"] || {}
    permissions.each do |permission, action|
      next if Ability.valid_action?(action)
      message = "'#{permission}' has an invalid action: '#{action}'."
      errors.add(:permission, message)
    end
  end
end
