# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("advanced_security_billing.billing_toggled") do |payload|
    message = { actor: serializer.user(payload[:actor]), toggle_state: payload[:toggle_state] }
    message[:organization] = serializer.organization(payload[:organization]) if payload[:organization]
    message[:business] = serializer.business(payload[:business]) if payload[:business]

    publish(message, schema: "advanced_security_billing.v0.BillingToggled")
  end
end

Hydro::EventForwarder.configure(source: GitHub) do
  subscribe("advanced_security_billing.ghas_metered_usage_locked") do |payload|
    sku = T::let(T::must(payload[:sku]), GitHub::Turboghas::SKU)

    if payload[:organization_id]
      GitHub.logger.info("ghas metered usage locked for organization", {
        "gh.sku": sku.to_param,
        "gh.org.id": payload[:organization_id],
        "gh.reason": payload[:reason],
      })

      # Send email notifications
      AdvancedSecurityMailer.metered_usage_locked_for_org(payload[:organization_id], sku, with_billing_link: true).deliver_later
      AdvancedSecurityMailer.metered_usage_locked_for_org(payload[:organization_id], sku, with_billing_link: false).deliver_later

      publish({
        organization_id: payload[:organization_id],
        locked: true,
        sku: sku.to_param,
        darkship: false,
        reason: payload[:reason],
      }, schema: "advanced_security_billing.v0.OrganizationMeteredUsageLockStatusChange")

      event = case sku
      when GitHub::Turboghas::SKU::Bundled
        "org.advanced_security_metered_usage_lock"
      when GitHub::Turboghas::SKU::CodeSecurity
        "org.code_security_metered_usage_lock"
      when GitHub::Turboghas::SKU::SecretSecurity
        "org.secret_protection_metered_usage_lock"
      end

      GitHub.instrument(event, {
        org_id: payload[:organization_id],
        reason: payload[:reason],
      })
    end

    if payload[:business_id]
      GitHub.logger.info("ghas metered usage locked for business", {
        "gh.sku": sku.to_param,
        "gh.business.id": payload[:business_id],
        "gh.reason": payload[:reason],
      })

      # Send email notifications
      AdvancedSecurityMailer.metered_usage_locked_for_enterprise(payload[:business_id], sku).deliver_later

      publish({
        business_id: payload[:business_id],
        locked: true,
        sku: sku.to_param,
        darkship: false,
        reason: payload[:reason],
      }, schema: "advanced_security_billing.v0.BusinessMeteredUsageLockStatusChange")

      event = case sku
      when GitHub::Turboghas::SKU::Bundled
        "business.advanced_security_metered_usage_lock"
      when GitHub::Turboghas::SKU::CodeSecurity
        "business.code_security_metered_usage_lock"
      when GitHub::Turboghas::SKU::SecretSecurity
        "business.secret_protection_metered_usage_lock"
      end

      GitHub.instrument(event, {
        business_id: payload[:business_id],
        reason: payload[:reason],
      })

    end
  end

  subscribe("advanced_security_billing.ghas_metered_usage_unlocked") do |payload|
    sku = T::let(T::must(payload[:sku]), GitHub::Turboghas::SKU)

    if payload[:organization_id]
      GitHub.logger.info("ghas metered usage unlocked for organization", {
        "gh.sku": sku.to_param,
        "gh.org.id": payload[:organization_id],
      })

      # Send email notifications
      AdvancedSecurityMailer.metered_usage_unlocked_for_org(payload[:organization_id], sku).deliver_later

      publish({
        organization_id: payload[:organization_id],
        locked: false,
        sku: sku.to_param,
        darkship: false,
        reason: "",
      }, schema: "advanced_security_billing.v0.OrganizationMeteredUsageLockStatusChange")

      event = case sku
      when GitHub::Turboghas::SKU::Bundled
        "org.advanced_security_metered_usage_unlock"
      when GitHub::Turboghas::SKU::CodeSecurity
        "org.code_security_metered_usage_unlock"
      when GitHub::Turboghas::SKU::SecretSecurity
        "org.secret_protection_metered_usage_unlock"
      end

      GitHub.instrument(event, {
        org_id: payload[:organization_id],
      })
    end

    if payload[:business_id]
      GitHub.logger.info("ghas metered usage unlocked for business", {
        "gh.sku": sku.to_param,
        "gh.business.id": payload[:business_id],
      })

      # Send email notifications
      AdvancedSecurityMailer.metered_usage_unlocked_for_enterprise(payload[:business_id], sku).deliver_later

      publish({
        business_id: payload[:business_id],
        locked: false,
        sku: sku.to_param,
        darkship: false,
        reason: "",
      }, schema: "advanced_security_billing.v0.BusinessMeteredUsageLockStatusChange")

      event = case sku
      when GitHub::Turboghas::SKU::Bundled
        "business.advanced_security_metered_usage_unlock"
      when GitHub::Turboghas::SKU::CodeSecurity
        "business.code_security_metered_usage_unlock"
      when GitHub::Turboghas::SKU::SecretSecurity
        "business.secret_protection_metered_usage_unlock"
      end

      GitHub.instrument(event, {
        business_id: payload[:business_id],
      })
    end
  end

  subscribe("advanced_security_billing.darkship.ghas_metered_usage_locked") do |payload|
    sku = T::let(T::must(payload[:sku]), GitHub::Turboghas::SKU)

    if payload[:organization_id]
      GitHub.logger.info("ghas metered usage locked for organization", {
        "gh.sku": sku.to_param,
        "gh.org.id": payload[:organization_id],
        "gh.reason": payload[:reason],
        "gh.darkship": true,
      })

      # no emails and audit logs for darkship
      publish({
        organization_id: payload[:organization_id],
        locked: true,
        sku: sku.to_param,
        darkship: true,
        reason: payload[:reason],
      }, schema: "advanced_security_billing.v0.OrganizationMeteredUsageLockStatusChange")
    end

    if payload[:business_id]
      GitHub.logger.info("ghas metered usage locked for business", {
        "gh.sku": sku.to_param,
        "gh.business.id": payload[:business_id],
        "gh.reason": payload[:reason],
        "gh.darkship": true,
      })

      # no emails and audit logs for darkship
      publish({
        business_id: payload[:business_id],
        locked: true,
        sku: sku.to_param,
        darkship: true,
        reason: payload[:reason],
      }, schema: "advanced_security_billing.v0.BusinessMeteredUsageLockStatusChange")
    end
  end
end
