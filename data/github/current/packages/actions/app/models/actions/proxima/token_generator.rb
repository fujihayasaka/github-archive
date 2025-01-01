# typed: true
# frozen_string_literal: true

class Actions::Proxima::TokenGenerator

  def initialize(**kwargs)
    @proxima_service_identity_secret_key = kwargs.fetch(:proxima_service_identity_secret_key) { ENV["PROXIMA_SERVICE_IDENTITY_SECRET_KEY"] }
  end

  attr_reader :connection, :app_id, :app_pem, :installation_id, :proxima_service_identity_secret_key

  sig { returns(String) }
  def generate_proxima_service_identity_token
    get_proxima_service_identity_token(proxima_service_identity_secret_key)
  end

  private

  def get_proxima_service_identity_token(proxima_service_identity_secret_key)
    token = ProximaServiceToken.generate(
      stamp: GitHub::Config::Proxima.current_stamp_or_dotcom,
      tenant_shortcode: GitHub::CurrentTenant.get&.shortcode,
      service_name: "actions",
      secret: proxima_service_identity_secret_key,
    )
  end
end
