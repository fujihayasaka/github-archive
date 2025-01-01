# typed: true
# frozen_string_literal: true

# This job imports the public keys of the GitHub Advanced Security integration.
class ImportAdvancedSecurityAppPublicKeysJob < ApplicationJob
  extend T::Sig
  extend T::Helpers

  queue_as :code_scanning

  schedule interval: 5.minutes, condition: -> { GitHub.multi_tenant_enterprise? }

  exempt_from_tenant_context_requirement
  retry_on_dirty_exit

  sig { void }
  def perform
    app_alias = :code_scanning

    integration = Apps::Internal.integration(app_alias)
    return if integration.nil?

    environment_variable_name = "APP_PUBLIC_KEY_#{app_alias.to_s.upcase}"
    public_key = ENV[environment_variable_name]
    return unless public_key

    ActiveRecord::Base.connected_to(role: :writing) do
      integration.public_keys.where(public_pem: public_key).first_or_create!(creator_id: integration.owner, skip_generate_key: true, public_pem: public_key)
    end
  end
end
