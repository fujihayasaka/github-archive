# typed: true
# frozen_string_literal: true

class Api::Enterprise::Settings < Api::App
  get "/enterprise/github/environment", operation_id: :we_forgot do
    @route_owner = "@github/meao"
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw(
      hostname: GitHub.host_name,
      ssl: GitHub.ssl?,
      private_mode: GitHub.private_mode_enabled?,
      rails_env: Rails.env,
      enterprise: GitHub.enterprise?,
    )
  end

  get "/enterprise/github/action_mailer", operation_id: :we_forgot do
    @route_owner = "@github/meao"

    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    payload = {
      raise_delivery_errors: ActionMailer::Base.raise_delivery_errors,
      delivery_method: ActionMailer::Base.delivery_method,
      perform_deliveries: ActionMailer::Base.perform_deliveries,
    }
    case ActionMailer::Base.delivery_method
    when :smtp
      payload[:smtp_settings] = ActionMailer::Base.smtp_settings
      password = payload[:smtp_settings][:password]
      password = password.nil? ? nil : "[filtered]"
      payload[:smtp_settings][:password] = password
    when :sendmail
      payload[:sendmail_settings] = ActionMailer::Base.sendmail_settings
    end

    deliver_raw payload
  end

  get "/enterprise/settings/smtp", operation_id: :we_forgot do
    @route_owner = "@github/meao"

    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw(
      port: GitHub.smtp_port,
      user: GitHub.smtp_user_name,
      password: GitHub.smtp_password.nil? ? nil : "[filtered]",
      domain: GitHub.smtp_domain,
      authentication: GitHub.smtp_authentication,
      starttls: GitHub.smtp_enable_starttls_auto,
      address: GitHub.smtp_address,
    )
  end

  get "/enterprise/settings/license", operation_id: "enterprise-admin/get-license-information" do
    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw(
      seats: GitHub::Enterprise.license.readable_seats,
      seats_used: GitHub::Enterprise.license.seats_used,
      seats_available: GitHub::Enterprise.license.readable_seats_available,
      kind: GitHub::Enterprise.license.kind,
      days_until_expiration: GitHub::Enterprise.license.days_until_expiration,
      expire_at: GitHub::Enterprise.license.expire_at,
    )
  end

  get "/enterprise/settings/auth", operation_id: :we_forgot do
    @route_owner = "@github/meao"

    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    payload = {
      mode: GitHub.auth_mode,
    }

    case GitHub.auth_mode.to_s
    when "ldap"
      payload.merge!(ldap_settings)
    when "cas"
      payload.merge!(cas_settings)
    end

    deliver_raw payload
  end

  get "/enterprise/settings/ldap", operation_id: :we_forgot do
    @route_owner = "@github/meao"

    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw ldap_settings
  end

  get "/enterprise/settings/cas", operation_id: :we_forgot do
    @route_owner = "@github/meao"

    unless trusted_port?
      control_access :enterprise,
        resource: GitHub.global_business,
        allow_integrations: false,
        allow_user_via_granular_actor: false
    end

    deliver_raw cas_settings
  end

  def ldap_settings
    {
      base: GitHub.ldap_base,
      password: GitHub.ldap_password.nil? ? nil : "[filtered]",
      profile_uid: GitHub.ldap_profile_uid,
      profile_name: GitHub.ldap_profile_name,
      profile_mail: GitHub.ldap_profile_mail,
      profile_public_key: GitHub.ldap_profile_key,
      host: GitHub.ldap_host,
      port: GitHub.ldap_port,
      method: GitHub.ldap_method,
      bind_dn: GitHub.ldap_bind_dn,
      admin_group: GitHub.ldap_admin_group,
      user_groups: GitHub.ldap_user_groups,
    }
  end

  def cas_settings
    { url: GitHub.cas_url }
  end
end
