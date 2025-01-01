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
    # This subscription currently only logs events. Missing functionality includes:
    # - Sending email notifications
    # - Adding audit log entries
    # Tracking issues:
    # https://github.com/github/secret-scanning/issues/12199
    # https://github.com/github/secret-scanning/issues/12198
    if payload[:organization_id]
      GitHub.logger.info("ghas metered usage locked for organization", {
        "gh.sku": payload[:sku],
        "gh.org.id": payload[:organization_id],
      })
    end

    if payload[:business_id]
      GitHub.logger.info("ghas metered usage locked for business", {
        "gh.sku": payload[:sku],
        "gh.business.id": payload[:business_id],
      })
    end
  end

  subscribe("advanced_security_billing.ghas_metered_usage_unlocked") do |payload|
    # This subscription currently only logs events. Missing functionality includes:
    # - Sending email notifications
    # - Adding audit log entries
    # Tracking issues:
    # https://github.com/github/secret-scanning/issues/12199
    # https://github.com/github/secret-scanning/issues/12198
    if payload[:organization_id]
      GitHub.logger.info("ghas metered usage unlocked for organization", {
        "gh.sku": payload[:sku],
        "gh.org.id": payload[:organization_id],
      })
    end

    if payload[:business_id]
      GitHub.logger.info("ghas metered usage unlocked for business", {
        "gh.sku": payload[:sku],
        "gh.business.id": payload[:business_id],
      })
    end
  end
end
