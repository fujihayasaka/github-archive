# typed: true
# frozen_string_literal: true

if ActionMailer::Base.delivery_method == :smtp
  settings = {
    domain: GitHub.smtp_domain,
    address: GitHub.smtp_address,
    port: GitHub.smtp_port,
    user_name: GitHub.smtp_user_name,
    password: GitHub.smtp_password,
    authentication: GitHub.smtp_authentication,
    enable_starttls_auto: GitHub.smtp_enable_starttls_auto,
    perform_deliveries: true,
  }

  # just in case the username and password were set when trying a different
  # authentication method and then switched to 'none'
  if settings[:authentication].blank?
    settings.delete(:user_name)
    settings.delete(:password)
  end

  settings.each_key { |key| settings.delete(key) if settings[key].nil? }

  ActionMailer::Base.smtp_settings = settings
end
