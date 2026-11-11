# typed: strict
# frozen_string_literal: true

class AdvancedSecurityMailer < ApplicationMailer
  include GitHub::RouteHelpers
  include GitHub::DatadogHelper
  include SecretScanning::Features::FeatureFlagHelper

  self.mailer_name = "mailers/advanced_security"

  layout "layouts/primer_layout"

  helper :avatar

  sig { params(org_id: Integer, sku: GitHub::Turboghas::SKU, with_billing_link: T::Boolean).returns(T.untyped) }
  def metered_usage_locked_for_org(org_id, sku, with_billing_link: true)
    success = false

    begin
      ActiveRecord::Base.connected_to(role: :reading) do
        org = Organization.find_by(id: org_id)
        if org
          return unless active_committers?(org, sku)
          return unless AdvancedSecurity::MeteredUsageService.new.sku_locked_for_entity?(org, sku)

          collected_users = with_billing_link ? collect_org_notification_users_with_billing_access(org) : collect_org_notification_users_without_billing_access(org)
          perform_metered_usage_locked_for_org(org, sku, collected_users, billing_access: with_billing_link) if collected_users.any?
        else
          # If Org was not found, it may be deleted. Log a warning.
          GitHub.logger.warn("Organization not found for ID: #{org_id}")
        end
      end
      success = true
    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      GitHub.logger.error(
        "Error processing advanced security mailer email",
        "code.namespace": self.class.name,
        "exception.message": e.message,
        "gh.org.id": org_id
      )
      GitHub.dogstats.increment("advanced_security.mailer.metered_usage.error", tags: ["method:#{__method__}"])
      raise e
    ensure
      GitHub.dogstats.increment("advanced_security.mailer.metered_usage.complete", tags: ["success:#{success}", "method:#{__method__}"])
    end
  end

  # Method overloading for product_unlocked_for_org to support either:
  # - an organization ID and SKU, or
  # - an organization object, SKU, and users list
  sig { params(org_id: Integer, sku: GitHub::Turboghas::SKU).returns(T.untyped) }
  def metered_usage_unlocked_for_org(org_id, sku)
    success = false

    begin
      ActiveRecord::Base.connected_to(role: :reading) do
        org = Organization.find_by(id: org_id)
        if org
          return unless active_committers?(org, sku)
          return if AdvancedSecurity::MeteredUsageService.new.sku_locked_for_entity?(org, sku)
          collected_users = collect_all_org_notification_users(org)
          perform_metered_usage_unlocked_for_org(org, sku, collected_users) if collected_users.any?
        else
          # If Org was not found, it may be deleted. Log a warning.
          GitHub.logger.warn("Organization not found for ID: #{org_id}")
        end
      end
      success = true
    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      GitHub.logger.error(
        "Error processing advanced security mailer email",
        "code.namespace": self.class.name,
        "exception.message": e.message,
        "gh.org.id": org_id
      )
      GitHub.dogstats.increment("advanced_security.mailer.metered_usage.error", tags: ["method:#{__method__}"])
      raise e
    ensure
      GitHub.dogstats.increment("advanced_security.mailer.metered_usage.complete", tags: ["success:#{success}", "method:#{__method__}"])
    end
  end

  sig { params(enterprise_id: Integer, sku: GitHub::Turboghas::SKU).returns(T.untyped) }
  def metered_usage_locked_for_enterprise(enterprise_id, sku)
    success = false

    begin
      ActiveRecord::Base.connected_to(role: :reading) do
        enterprise = Business.find_by(id: enterprise_id)
        if enterprise
          return unless active_committers?(enterprise, sku)
          return unless AdvancedSecurity::MeteredUsageService.new.sku_locked_for_entity?(enterprise, sku)
          collected_users = collect_enterprise_notification_users(enterprise)
          perform_metered_usage_locked_for_enterprise(enterprise, sku, collected_users) if collected_users.any?
        else
          # If Enterprise was not found, it may be deleted. Log a warning.
          GitHub.logger.warn("Enterprise not found for ID: #{enterprise_id}")
        end
      end
      success = true
    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      GitHub.logger.error(
        "Error processing advanced security mailer email",
        "code.namespace": self.class.name,
        "exception.message": e.message,
        "gh.business.id": enterprise_id
      )
      GitHub.dogstats.increment("advanced_security.mailer.metered_usage.error", tags: ["method:#{__method__}"])
      raise e
    ensure
      GitHub.dogstats.increment("advanced_security.mailer.metered_usage.complete", tags: ["success:#{success}", "method:#{__method__}"])
    end
  end

  # Method overloading for product_unlocked_for_enterprise to support either:
  # - an enterprise ID and SKU, or
  # - an enterprise object, SKU, and users list
  sig { params(enterprise_id: Integer, sku: GitHub::Turboghas::SKU).returns(T.untyped) }
  def metered_usage_unlocked_for_enterprise(enterprise_id, sku)
    success = false

    begin
      ActiveRecord::Base.connected_to(role: :reading) do
        enterprise = Business.find_by(id: enterprise_id)
        if enterprise
          return unless active_committers?(enterprise, sku)
          return if AdvancedSecurity::MeteredUsageService.new.sku_locked_for_entity?(enterprise, sku)
          collected_users = collect_enterprise_notification_users(enterprise)
          perform_metered_usage_unlocked_for_enterprise(enterprise, sku, collected_users) if collected_users.any?
        else
          # If Enterprise was not found, it may be deleted. Log a warning.
          GitHub.logger.warn("Enterprise not found for ID: #{enterprise_id}")
        end
      end
      success = true
    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      GitHub.logger.error(
        "Error processing advanced security mailer email",
        "code.namespace": self.class.name,
        "exception.message": e.message,
        "gh.business.id": enterprise_id
      )
      GitHub.dogstats.increment("advanced_security.mailer.metered_usage.error", tags: ["method:#{__method__}"])
      raise e
    ensure
      GitHub.dogstats.increment("advanced_security.mailer.metered_usage.complete", tags: ["success:#{success}", "method:#{__method__}"])
    end
  end

  sig { params(org: ::Organization, sku: GitHub::Turboghas::SKU, users: T::Array[::User], billing_access: T::Boolean).returns(T.untyped) }
  def perform_metered_usage_locked_for_org(org, sku, users, billing_access: true)
    users = users.select { |user| allow_sending_to_email?(user, org) }
    recipients = build_admin_recipients_list(org, users)
    return nil unless recipients[:to].any? || recipients[:bcc].any?

    @org = org
    @sku_string = get_sku_string(sku)
    @footer = "You are receiving this email because #{@sku_string} features cannot be enabled."
    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ]
    @billing_access = T.let(billing_access, T.nilable(T::Boolean))

    subject = "Action Required: Billing issue affecting your #{@sku_string} products"

    message_id = generate_locked_message_id(org, sku)
    email_headers = email_headers(message_id)

    headers(email_headers)

    premail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: subject,
    )
  end

  sig { params(org: ::Organization, sku: GitHub::Turboghas::SKU, users: T::Array[::User]).returns(T.untyped) }
  def perform_metered_usage_unlocked_for_org(org, sku, users)
    users = users.select { |user| allow_sending_to_email?(user, org) }
    recipients = build_admin_recipients_list(org, users)
    return nil unless recipients[:to].any? || recipients[:bcc].any?

    @org = T.let(org, T.nilable(Organization))
    @sku_string = T.let(get_sku_string(sku), T.nilable(String))
    @footer = T.let("You are receiving this email because #{@sku_string} features can now be enabled.", T.nilable(String))
    @footer_links = T.let([
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ], T.nilable(T::Array[T::Hash[Symbol, String]]))

    subject = "Billing Issue Resolved: #{@sku_string} enablement unlocked"

    message_id = generate_unlocked_message_id(org, sku)
    email_headers = email_headers(message_id)

    headers(email_headers)

    premail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: subject,
    )
  end

  sig { params(enterprise: ::Business, sku: GitHub::Turboghas::SKU, users: T::Array[::User]).returns(T.untyped) }
  def perform_metered_usage_locked_for_enterprise(enterprise, sku, users)
    users = users.select { |user| allow_sending_to_email?(user, enterprise) }
    recipients = build_admin_recipients_list(enterprise, users)
    return nil unless recipients[:to].any? || recipients[:bcc].any?

    @enterprise = T.let(enterprise, T.nilable(Business))
    @sku_string = T.let(get_sku_string(sku), T.nilable(String))
    @footer = "You are receiving this email because #{@sku_string} features cannot be enabled."
    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ]

    subject = "Action Required: Billing issue affecting your #{@sku_string} products"

    message_id = generate_enterprise_locked_message_id(enterprise, sku)
    email_headers = email_headers(message_id)

    headers(email_headers)

    premail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: subject,
      template_name: "metered_usage_locked_for_enterprise",
    )
  end

  sig { params(enterprise: ::Business, sku: GitHub::Turboghas::SKU, users: T::Array[::User]).returns(T.untyped) }
  def perform_metered_usage_unlocked_for_enterprise(enterprise, sku, users)
    users = users.select { |user| allow_sending_to_email?(user, enterprise) }
    recipients = build_admin_recipients_list(enterprise, users)
    return nil unless recipients[:to].any? || recipients[:bcc].any?

    @enterprise = enterprise
    @sku_string = get_sku_string(sku)
    @footer = "You are receiving this email because #{@sku_string} features can now be enabled."
    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" }
    ]

    subject = "Billing Issue Resolved: #{@sku_string} enablement unlocked"

    message_id = generate_enterprise_unlocked_message_id(enterprise, sku)
    email_headers = email_headers(message_id)

    headers(email_headers)

    premail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: subject,
      template_name: "metered_usage_unlocked_for_enterprise",
    )
  end

  private

  sig { params(sku: GitHub::Turboghas::SKU).returns(String) }
  def get_sku_string(sku)
    case sku
    when GitHub::Turboghas::SKU::Bundled
      "GitHub Advanced Security"
    when GitHub::Turboghas::SKU::CodeSecurity
      "GitHub Code Security"
    when GitHub::Turboghas::SKU::SecretSecurity
      "GitHub Secret Protection"
    end
  end

  sig { params(user: User, owner: T.any(Repository, Organization, Business)).returns(T::Boolean) }
  def allow_sending_to_email?(user, owner)
    if owner.is_a?(Repository)
      repo_owner = owner.owner
      if repo_owner.is_a?(Organization)
        return repo_owner.user_can_receive_email_notifications?(user)
      end
    elsif owner.is_a?(Organization)
      return owner.user_can_receive_email_notifications?(user)
    else
      # TODO: support email filtering for business scope
      # https://github.com/github/secret-scanning/issues/7639
    end

    true
  end

  sig { params(message_id: String, references: T::Array[String]).returns(T::Hash[String, String]) }
  def email_headers(message_id, references = [])
    email_headers = {
      "Message-Id" => message_id,

      "X-GitHub-Sender" => GitHub.trusted_oauth_apps_org_name,
      "X-GitHub-Reason" => "advanced-security-product-status",
    }

    if references.any?
      email_headers["In-Reply-To"] = references.last
      email_headers["References"] = references.join(" ")
    end

    email_headers
  end

  # Message-Id needs to be globally unique
  sig { params(org: Organization, sku: GitHub::Turboghas::SKU).returns(String) }
  def generate_locked_message_id(org, sku)
    timestamp = Time.now.to_i
    "<advanced-security-summary/#{org.display_login}/#{sku.to_param}/locked/#{timestamp}@#{GitHub.urls.host_name}>"
  end

  # Message-Id needs to be globally unique
  sig { params(org: Organization, sku: GitHub::Turboghas::SKU).returns(String) }
  def generate_unlocked_message_id(org, sku)
    timestamp = Time.now.to_i
    "<advanced-security-summary/#{org.display_login}/#{sku.to_param}/unlocked/#{timestamp}@#{GitHub.urls.host_name}>"
  end

  # Message-Id needs to be globally unique
  sig { params(enterprise: Business, sku: GitHub::Turboghas::SKU).returns(String) }
  def generate_enterprise_locked_message_id(enterprise, sku)
    timestamp = Time.now.to_i
    "<advanced-security-summary/enterprise/#{enterprise.id}/#{sku.to_param}/locked/#{timestamp}@#{GitHub.urls.host_name}>"
  end

  # Message-Id needs to be globally unique
  sig { params(enterprise: Business, sku: GitHub::Turboghas::SKU).returns(String) }
  def generate_enterprise_unlocked_message_id(enterprise, sku)
    timestamp = Time.now.to_i
    "<advanced-security-summary/enterprise/#{enterprise.id}/#{sku.to_param}/unlocked/#{timestamp}@#{GitHub.urls.host_name}>"
  end

  sig { params(org: ::Organization).returns(T::Array[::User]) }
  def collect_all_org_notification_users(org)
    user_ids = T.let(
      org.billing_managers.pluck(:id) +
      org.admins.pluck(:id) +
      SecurityProduct::SecurityManagers.new(org).users.pluck(:id),
      T::Array[::Integer]
    )
    User.where(id: user_ids).to_a
  end

  sig { params(org: ::Organization).returns(T::Array[::User]) }
  def collect_org_notification_users_without_billing_access(org)
    user_ids_with_billing_access = collect_org_notification_users_with_billing_access_ids(org)

    user_ids = T.let(
      SecurityProduct::SecurityManagers.new(org).users.pluck(:id),
      T::Array[::Integer]
    )
    user_ids -= user_ids_with_billing_access
    User.where(id: user_ids).to_a
  end

  sig { params(org: ::Organization).returns(T::Array[::User]) }
  def collect_org_notification_users_with_billing_access(org)
    User.where(id: collect_org_notification_users_with_billing_access_ids(org)).to_a
  end

  sig { params(org: ::Organization).returns(T::Array[::Integer]) }
  def collect_org_notification_users_with_billing_access_ids(org)
    org.billing_managers.pluck(:id) +
      org.admins.pluck(:id)
  end

  sig { params(enterprise: ::Business).returns(T::Array[::User]) }
  def collect_enterprise_notification_users(enterprise)
    user_ids = T.let(
      enterprise.owners.pluck(:id) +
      enterprise.billing_managers.pluck(:id),
      T::Array[::Integer]
    )
    User.where(id: user_ids).to_a
  end

  sig { params(entity: T.any(Organization, Business), sku: GitHub::Turboghas::SKU).returns(T::Boolean) }
  def active_committers?(entity, sku)
    entity.advanced_security_license_for_sku(sku: sku).entity_summary.active_committers > 0
  end
end
