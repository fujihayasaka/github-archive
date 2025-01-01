# typed: true
# frozen_string_literal: true

class SamlProviderSetupFlow
  attr_accessor :target, :tmp_provider

  def initialize(target)
    @target = target
    @tmp_provider = get_tmp_provider(recovery_secret)
  end

  # Build a temporary SAML provider, based on provided SAML configuration
  # values, and store the recovery secret in GitHub.kv, without persisting the
  # SAML provider. If the provided values result in an invalid SAML provider,
  # the recovery secret isn't stored.
  #
  # saml_params - Hash of parameters that can be used to assign values to a
  #   temporary SAML provider.
  #
  # Returns nothing.
  def new_setup(saml_params)
    @tmp_provider = get_tmp_provider
    @tmp_provider.generate_recovery!
    @tmp_provider.assign_attributes saml_params
    return unless @tmp_provider.valid?

    ExternalIdentities::KV.set(kv_key, "#{@tmp_provider.recovery_secret}", expires: 1.hour.from_now)
  end

  def recovery_secret
    ExternalIdentities::KV.get(kv_key).value!
  end

  def pending?
    recovery_secret.present?
  end

  def clear_kv_values
    ExternalIdentities::KV.del(kv_key)
  end

  private

  def kv_key
    "saml_provider_setup_recovery_secret:#{target_type}:#{target.id}"
  end

  def get_tmp_provider(recovery_secret = false)
    provider_class.new(target: target).tap do |provider|
      provider.recovery_secret = recovery_secret if recovery_secret
      provider.recovery_used_bitfield = 0
    end
  end

  def provider_class
    case target
    when ::Business
      Business::SamlProvider
    when ::Organization
      Organization::SamlProvider
    else
      raise ArgumentError, "target must be a Business or Organization"
    end
  end

  def target_type
    case target
    when ::Business
      "business"
    when ::Organization
      "organization"
    else
      raise ArgumentError, "target must be a Business or Organization"
    end
  end
end
