# typed: true
# frozen_string_literal: true

class BillingNotificationsMailer < ApplicationMailer

  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/billing_notifications"

  layout "layouts/primer_layout"

  include BillingSettingsHelper
  helper :billing_settings

  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::NumberHelper
  helper :text

  # Public: Email a User/Organization/Business a payment receipt.
  #
  # account - The User/Organization/Business that was billed.
  # billing_transaction - A Billing::BillingTransaction (or equivalent).
  #
  # Returns an ActionMailer Mail object.
  def receipt(account, billing_transaction)
    @account = account
    @receipt = ::Billing::Receipt.new(billing_transaction)
    @extra   = @account.try(:billing_extra)

    attachments[@receipt.pdf_filename] = {
      mime_type: "application/pdf",
      content: @receipt.to_pdf,
    }

    recipients = user_or_billing_recipients(account)

    mail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: "[GitHub] Payment Receipt for #{@account}",
    )
  end

  # Public: Email to bcc_log about a payment receipt.
  #
  # account - The User/Organization/Business that was billed.
  # billing_transaction - A Billing::BillingTransaction (or equivalent).
  #
  # Returns an ActionMailer Mail object.
  def receipt_bcc(account, billing_transaction)
    @account = account
    @receipt = ::Billing::Receipt.new(billing_transaction)
    @extra   = @account.try(:billing_extra)

    mail(
      from: github_noreply,
      to: bcc_log,
      subject: "[GitHub] Payment Receipt (#{account.billing_email})",
      template_name: "receipt",
    )
  end

  def self.send_receipt_bcc?
    Helpers.bcc_log.any?
  end

  # Public: Email a receipt for a refund.
  #
  # user                   - The User/Organization that was billed.
  # purchased_on           - The date of purchase
  # refund_amount_in_cents - Integer amount in cents of the refund.
  # refunded_at            - The refund transaction timestamp, as Time
  # custom_text            - Optional custom text to include in the email (e.g. reason for the refund)
  #
  # Returns an ActionMailer Mail object.
  def refund(user, purchased_on, refund_amount_in_cents, instrument, refunded_at = nil, custom_text = nil, old_refund_transaction = nil, refund_transaction:)
    refund_transaction ||= old_refund_transaction
    refunded_at = refund_transaction&.created_at || Time.current
    @account = refund_transaction&.billable_entity || user
    @sale_date = purchased_on.to_formatted_s(:long)
    @refunded_at = refunded_at.to_formatted_s(:long)
    @refund_amount = Billing::Money.new(refund_amount_in_cents).dollars
    @instrument = instrument
    @custom_text = custom_text
    @receipt = nil

    if refund_transaction
      @receipt = ::Billing::Receipt.new(refund_transaction)
      @refund_amount = @receipt.amount.dollars.abs
      @refunded_at = (@receipt.created_at || Time.current).to_formatted_s(:long)

      attachments[@receipt.pdf_filename] = {
        mime_type: "application/pdf",
        content: @receipt.to_pdf,
      }
    end

    recipients = user_or_billing_recipients(@account)

    mail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: "[GitHub] Refund Receipt",
    )
  end

  def free_trial_will_end_soon(user, subscription_item_change)
    @user = user
    @subscription_item_change = subscription_item_change
    @marketplace_listing_plan_name = subscription_item_change.subscribable.name
    @marketplace_listing_name = subscription_item_change.subscribable.listing.name
    @settings_url = target_billing_url(@user)
    @subject = "Your free trial for #{@marketplace_listing_name} is ending soon"
    @footer_text = "You are receiving this email because the #{@user} account has a free trial that will end soon."
    @footer_links = [
      { url: target_billing_url(user), text: "View billing settings" },
      { url: contact_url, text: "Contact us" }
    ]
    recipients = user_or_billing_recipients(user)

    premail(
      from:       github_noreply,
      to:         recipients[:to],
      bcc:        recipients[:bcc].concat(bcc_log),
      subject:    "[GitHub] " + @subject,
      categories: "free-trial-ending-reminder",
    )
  end

  sig { params(billable_entity: ::Billing::Types::Account, redemption: CouponRedemption).void }
  def coupon_will_expire_soon(billable_entity, redemption)
    @billable_entity = billable_entity
    @redemption = redemption
    @coupon = redemption.coupon
    @payment_amount = Billing::Money.new(billable_entity.undiscounted_payment_amount * 100).format(no_cents_if_whole: true)
    @help_url = payment_information_help_url(billable_entity)
    @settings_url = payment_information_settings_url(billable_entity)
    @subject = "Coupon expiration reminder"
    @footer_text = "You are receiving this email because the #{@billable_entity} account has a coupon that will expire soon."
    @footer_links = [
      { url: target_billing_url(billable_entity), text: "View billing settings" },
      { url: contact_url, text: "Contact us" }
    ]
    recipients = user_or_billing_recipients(billable_entity)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
      categories: "coupon-expiration-reminder",
    )
  end

  # Public: Email a reminder about an expiring credit card.
  #
  # account - The User/Organization/Business to remind.
  #
  # Returns an ActionMailer Mail object.
  def credit_card_will_expire_soon(account)
    @account = account
    @card_info = if @account.payment_method.present? && @account.payment_method.last_four.present?
      " (#{@account.payment_method.card_type} - #{@account.payment_method.formatted_number})"
    else
      ""
    end

    @on_file_text = if @account.is_a?(Business)
      "for the #{@account.name} enterprise"
    elsif @account.organization?
      "for the @#{@account.display_login} organization"
    else
      "on your GitHub account"
    end

    @settings_url = payment_information_settings_url(account)

    @subject = "Credit or debit card expiring soon"
    @subject += " for #{@account.safe_profile_name}" unless @account.user?
    @footer_text = "You are receiving this email because the credit or debit card on the #{@account} account will expire soon."
    @footer_links = [
      { url: @help_url, text: "Billing help" },
      { url: contact_url, text: "Contact us" }
    ]

    recipients = user_or_billing_recipients(account)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
      categories: "card-expiration-reminder",
    )
  end

  # Public: Email accounting that a yearly plan has been upgraded/downgraded.
  #
  # user          - The User that changed their plan.
  # old_plan_name - The previous Plan they had.
  # new_plan_name - The new Plan they have moved to.
  # delta_cost    - The calculated delta cost we charged/refunded the user.
  #
  # Returns an ActionMailer Mail object.
  def yearly_plan_change(user, old_plan, new_plan, delta_cost)
    @billing_date  = user.billed_on.to_s
    @user          = user
    @new_plan      = new_plan
    @old_plan_name = old_plan.display_name.capitalize
    @new_plan_name = new_plan.display_name.capitalize
    @delta_cost    = delta_cost

    mail(
      from: github_noreply,
      to: "ar@github.com, #{GitHub.support_email}",
      bcc: bcc_log,
      subject: "#{user.display_login} changed their yearly plan",
    )
  end

  # Public: Email alerting an account that their annual subscription will be billed soon
  sig { params(account: ::Billing::Types::Account, next_billing_date: T.nilable(Date)).void }
  def yearly_billing_notice(account, next_billing_date = nil)
    @account      = account
    @billing_date = next_billing_date || account.next_billing_date&.to_formatted_s(:long)
    @settings_url = target_billing_url(account)
    @subject      = "Annual Billing Alert for @#{@account.display_login}"
    @footer_text  = "You are receiving this email because you have an annual subscription on your GitHub account."
    @footer_links = [
      { url: @help_url, text: "Billing help" },
      { url: contact_url, text: "Contact us" }
    ]

    recipients = user_or_billing_recipients(account)

    premail(
      from:    github_noreply,
      to:      recipients[:to],
      bcc:     recipients[:bcc],
      subject: "[GitHub] " + @subject,
    )
  end

  def cc_expired_failure(account)
    @account = account
    @metered_billing_failure_text = metered_billing_failure_text(account)

    @help_url = payment_information_help_url(account)
    @settings_url = payment_information_settings_url(account)
    @subject = "Your credit card has expired"
    @footer_text = "You are receiving this email because the #{@account} account has an expired credit card."
    @footer_links = [
      { url: @help_url, text: "Billing help" },
      { url: contact_url, text: "Contact us" }
    ]
    recipients = user_or_billing_recipients(account)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  def cc_failure(account, message)
    @account = account
    @message = message
    @metered_billing_failure_text = metered_billing_failure_text(account)

    @help_url = payment_information_help_url(account)
    @settings_url = payment_information_settings_url(account)
    @subject = "We had a problem billing your account"
    @footer_text = "You are receiving this email because we had a problem billing your account."
    @footer_links = [
      { url: @help_url, text: "Billing help" },
      { url: contact_url, text: "Contact us" }
    ]

    recipients = user_or_billing_recipients(account)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  def paypal_failure(account, message)
    @account = account
    @message = message
    @metered_billing_failure_text = metered_billing_failure_text(account)

    latest_failed_transaction = account.billing_transactions
      .current
      .processor_declined
      .last

    # If we can find a failed transaction, we'll advise the customer to ensure their account has a sufficent
    # balance to cover the charge.
    #
    # Otherwise, we'll only provide the base troubleshooting tips. In general, it's expected for a payment
    # transaction to be found, but it's possible our workers get backed up and we move into a new billing
    # period for the customer.
    @amount_in_cents = latest_failed_transaction&.amount_in_cents

    @help_url = payment_information_help_url(account, for_paypal: true)
    @settings_url = payment_information_settings_url(account)
    @subject = "We had a problem billing your account"
    @footer_text = "You are receiving this email because we had a problem billing your account."
    @footer_links = [
      { url: @help_url, text: "Billing help" },
      { url: contact_url, text: "Contact us" }
    ]

    recipients = user_or_billing_recipients(account)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  def no_payment_failure(account)
    @account = account
    @message = message
    @metered_billing_failure_text = metered_billing_failure_text(account)

    @help_url = payment_information_help_url(account)
    @settings_url = payment_information_settings_url(account)
    @subject = "We had a problem billing your account"
    @footer_text = "You are receiving this email because we had a problem billing your account."
    @footer_links = [
      { url: @help_url, text: "Billing help" },
      { url: contact_url, text: "Contact us" }
    ]

    recipients = user_or_billing_recipients(account)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  sig { params(billable_entity: ::Billing::Types::Account, education_coupon: T::Boolean).void }
  def coupon_expired_failure(billable_entity, education_coupon: false)
    @billable_entity = billable_entity
    @education_coupon = billable_entity.coupon&.education_coupon? || education_coupon
    @help_url = payment_information_help_url(billable_entity)
    @settings_url = payment_information_settings_url(billable_entity)
    @subject = "Your coupon has expired"
    @footer_text = "You are receiving this email because the #{@billable_entity} account has an expired coupon."
    @footer_links = [
      { url: target_billing_url(billable_entity), text: "View billing settings" },
      { url: contact_url, text: "Contact us" }
    ]
    recipients = user_or_billing_recipients(billable_entity)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  sig { params(business: Business, education_coupon: T::Boolean).void }
  def business_coupon_expired(business, education_coupon: false)
    @business = business
    @payment_method_on_file = business.has_valid_payment_method?(feature_type: :noncommercial)
    @education_coupon = education_coupon
    @help_url = payment_information_help_url(business)
    @payment_settings_url = payment_information_settings_url(business)
    @downgrade_url = "#{GitHub.help_url}/enterprise-cloud@latest/billing/managing-the-plan-for-your-github-account/downgrading-your-accounts-plan#downgrading-your-enterprise-accounts-plan"
    @subject = "Your coupon has expired"
    @footer_text = "You are receiving this email because the #{@business} Enterprise account has an expired coupon."
    @footer_links = [
      { url: target_billing_url(business), text: "View billing settings" },
      { url: contact_url, text: "Contact us" }
    ]
    recipients = user_or_billing_recipients(business)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  # Public: Notify organization owners that the upgrade has timed out
  #
  # organization - The Organization that was being upgraded.
  #
  def organization_upgrade_failure(organization)
    @organization = organization
    @org_plan_url = settings_org_plans_path(organization)
    @subject = "Your organization upgrade has expired"
    @footer_text = "You are receiving this email because the #{@organization} account has an expired upgrade"
    @footer_links = [
      { url: target_billing_url(organization), text: "View organization billing settings" },
      { url: contact_url, text: "Contact us" }
    ]
    premail(
      from: github_noreply,
      to: admin_emails(organization),
      subject: "[GitHub] " + @subject,
    )
  end

  # Public: Notify organization admins that a coupon has been removed from their
  # organization since it has been transferred into an enterprise.
  #
  # organization - The Organization that is being invited into the enterprise.
  # business - The Business.
  #
  def coupon_removed_from_enterprise_owned_organization(organization, business)
    @organization = organization
    @business = business
    @help_url = payment_information_help_url(organization)
    @subject = "Your coupon has expired"
    @footer_text = "You are receiving this email because the #{@organization} account has an expired coupon."
    @footer_links = [
      { url: target_billing_url(business), text: "View enterprise billing settings" },
      { url: contact_url, text: "Contact us" }
    ]

    premail(
      from: github_noreply,
      to: admin_emails(@organization),
      subject: "[GitHub] " + @subject,
    )
  end

  def resources_usage(owner, content, content_owner: nil)
    @owner = owner
    @content = content
    content_owner ||= owner

    @subject = "#{@content.mail_subject} for the #{account_description(content_owner)}"
    @footer_text = if owner.user?
      "You are receiving this because you used a metered GitHub service with the #{account_description(content_owner)}."
    else
      "You are receiving this because you are an administrator or Billing Manager for an organization within the #{account_description(content_owner)}."
    end

    recipients = build_metered_billing_recipients_list(owner)

    @footer_links = [
      { url: target_billing_url(owner), text: "View billing settings" },
      { url: contact_url, text: "Contact us" }
    ]

    premail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
      template_name: "resources_usage_v2"
    )
  end

  def marketplace_failure(account, message)
    @account = account
    @message = message

    @help_url = payment_information_help_url(account)
    @settings_url = payment_information_settings_url(account)
    @sponsorships = !account.is_a?(Business) && account.actively_sponsoring? ? "or active sponsorships " : ""
    @subject = "We had a problem billing your account"
    @footer_text = "You are receiving this email because we had a problem billing your account."
    @footer_links = [
      { url: @help_url, text: "Billing help" },
      { url: contact_url, text: "Contact us" }
    ]

    recipients = user_or_billing_recipients(account)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  def never_entered_dunning_failure(account, message)
    @account = account
    @message = message

    @help_url = payment_information_help_url(account, for_paypal: account.has_paypal_account?)
    @settings_url = payment_information_settings_url(account)
    @subject = "We had a problem billing your account"
    @footer_text = "You are receiving this email because we had a problem billing your account."
    @footer_links = [
      { url: @help_url, text: "Billing help" },
      { url: contact_url, text: "Contact us" }
    ]

    recipients = user_or_billing_recipients(account)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  def over_billing_attempts_limit_failure(account, message)
    @account = account
    @message = message

    @help_url = payment_information_help_url(account, for_paypal: account.has_paypal_account?)
    @settings_url = payment_information_settings_url(account)

    recipients = user_or_billing_recipients(account)
    @subject = "We had a problem billing your account"
    @footer_text = "You are receiving this because we had a problem billing your account."
    @footer_links = [
      { url: target_billing_url(account), text: "Billing settings" },
      { url: @help_url, text: "Help" },
      { url: contact_url, text: "Contact us" }
    ]

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  def bundled_license_assignment_created(assignment)
    @email = assignment.email
    @business = assignment.business
    @footer_text = "You are receiving this because you have been assigned a GitHub Enterprise license."
    @footer_links = [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: settings_notification_preferences_url, text: "Notification settings" }
    ]

    premail(
        from: github_noreply,
        to: @email,
        subject: "You have been assigned a GitHub Enterprise license"
      )
  end

  def manual_dunning_attempts(account, notification_number)
    @account = account
    @notification_number = notification_number

    @subject = if notification_number.zero?
      "Your outstanding balance is available to pay"
    elsif notification_number == 1
      "Reminder: Your outstanding balance is due for payment"
    else
      "Final Reminder: Outstanding balance is due for payment"
    end

    recipients = user_or_billing_recipients(account)

    @footer_text = if @account.user?
      "You are receiving this because you used a metered GitHub service with the #{account_description(account)}."
    else
      "You are receiving this because you are an administrator or Billing Manager for an organization within the #{account_description(account)}."
    end

    @footer_links = [
      { url: target_billing_url(account), text: "View billing settings" },
      { url: contact_url, text: "Contact us" }
    ]

    premail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject
    )
  end

  sig { params(user_emails: T::Array[String], owner: T.any(Organization, Business), email_context: Hash).void }
  def budget_threshold_notification(user_emails:, owner:, email_context:)
    @email_context = ::Billing::Notifications::ThresholdEmailContext.from_hash(email_context)

    @owner = owner

    @subject = "#{@email_context.mail_subject} for the #{account_description(@owner)}"
    @footer_text = "You are receiving this because you are added as one of the recipients of this budget's alerts."

    premail(
      from: github,
      bcc: user_emails,
      subject: "[GitHub] " + @subject,
    )
  end

  sig { params(tax_exemption_status: Billing::TaxExemptionStatus).void }
  def tax_exemption_certificate_uploaded(tax_exemption_status)
    @account = tax_exemption_status.account
    url_options = { host: GitHub.admin_host_name, protocol: "https" }

    @stafftools_link = if @account.is_a?(Business)
      stafftools_enterprise_billing_url(@account, **url_options)
    else
      billing_stafftools_user_url(@account, **url_options)
    end

    customer = T.must(tax_exemption_status.customer)
    begin
      handler = Billing::Taxes::CertificateHandler.new(customer: customer)
      certificate_filedata = handler.download_certificate
    rescue StandardError => e # rubocop:disable Lint/GenericRescue
      Failbot.report(e)
      GitHub.logger.error({
        exception: e,
        "gh.customer.id": customer.id,
        "gh.billing.tax_exemption_status.id": tax_exemption_status.id
      })
    end

    # Get the file extension
    ext = File.extname(T.must(tax_exemption_status.certificate_name))

    # Construct filename
    # Filename convention - https://github.com/github/billing-core/issues/138#issuecomment-1942031297
    profile = @account.trade_screening_record
    @state = profile.region || "NONE"
    attachment_filename = "#{@state}_#{@account.class.name}_#{@account.id}_#{@account.display_login}#{ext}"
    @subject = "Tax exemption certificate uploaded for #{@account.display_login} from #{@state}"

    # Attach the file to the email
    attachments[attachment_filename] = certificate_filedata

    mail(
      from: github_noreply,
      to: "tax-exemptions@github.com",
      subject: "[GitHub] #{@subject}"
    )
  end

  sig { params(tax_exemption_status: Billing::TaxExemptionStatus).void }
  def tax_exemption_certificate_rejected(tax_exemption_status)
    @account = tax_exemption_status.account
    @status_reason = tax_exemption_status.status_reason
    @settings_url = target_billing_url(@account, tab: :payment_information)
    @subject = "Tax exemption certificate rejected"

    recipients = user_or_billing_recipients(@account)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] #{@subject}"
    )
  end

  sig { params(config: BillingPlatformEnabledProduct).void }
  def billing_platform_planned_migration_notice(config)
    customer = config.customer
    return unless customer

    @billable_entity = T.must(customer.billable_owner)
    @display_name = @billable_entity.name
    @migration_date = config.planned_migration_date&.utc&.strftime("%B %d, %Y %Z")

    @using_billing_platform_url = "#{GitHub.help_url}/enterprise-cloud@latest/billing/using-the-enhanced-billing-platform-for-enterprises"
    @billing_platform_budget_url = "#{GitHub.help_url}/enterprise-cloud@latest/billing/using-the-enhanced-billing-platform-for-enterprises/preventing-overspending"
    @billing_platform_lfs_url = "#{GitHub.help_url}/enterprise-cloud@latest/billing/using-the-enhanced-billing-platform-for-enterprises/about-enhanced-billing-for-git-large-file-storage"
    @billing_platform_rest_api_url = "#{GitHub.help_url}/enterprise-cloud@latest/rest/enterprise-admin/billing?apiVersion=2022-11-28"

    @subject = "Upcoming migration to a new billing platform for #{@display_name}"
    recipients = user_or_billing_recipients(@billable_entity)

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] " + @subject,
    )
  end

  private

  def payment_information_help_url(account, for_paypal: false)
    if account.is_a?(Business)
      # TODO: Implement correct enterprise PayPal and credit card URLs when made available
      GitHub.help_url
    elsif account.organization?
      for_paypal ? GitHub.org_paypal_help_url : GitHub.org_cc_help_url
    else
      for_paypal ? GitHub.personal_paypal_help_url : GitHub.personal_cc_help_url
    end
  end

  def payment_information_settings_url(account)
    if account.is_a?(Business)
      settings_billing_tab_enterprise_url(account, tab: "payment_information", host: GitHub.urls.host_name)
    elsif account.organization?
      settings_org_billing_tab_url(account, tab: "payment_information", host: GitHub.urls.host_name)
    else
      settings_user_billing_tab_url(tab: "payment_information", host: GitHub.urls.host_name)
    end
  end

  # Generates a recipient list for metered billing emails
  #
  # We want these sent to both billing managers and admins. Primarily because admins
  # have more context around Actions/Packages/Storage usage and billing managers may not.
  #
  # User accounts: just the user
  # Org owned accounts: all admins + billing managers
  # Enterprise accounts: all child org admins + enterprise billing managers
  #
  # Emails are sent on BCC to protect private email addresses from other Org users.
  def build_metered_billing_recipients_list(owner)
    if owner.is_a? Business
      billing_emails = billing_emails(owner)

      recipients = { to: [], bcc: [] }

      recipients[:bcc] << billing_emails
      recipients[:bcc].compact!

      return recipients
    end

    if owner.user?
      return user_or_billing_recipients(owner)
    end

    if owner.organization?
      recipients = build_admin_recipients_list(owner, owner.admins)

      unless owner.delegate_billing_to_business?
        recipients[:bcc] << billing_emails(owner)
      end

      recipients[:bcc].compact!

      recipients
    end
  end

  def metered_billing_failure_text(owner)
    restricted_by_payment_issue = Billing::UsageChecker.new(account: owner, product_names: []).paid_overages_restricted_by_owner_payment_issue?
    if restricted_by_payment_issue
      "Actions and Packages usage is restricted to the included amounts for your plan."
    else
      "If our next billing attempt fails, Actions and Packages usage will be restricted to the included amounts for your plan."
    end
  end

  def account_description(owner)
    if owner.is_a?(Business)
      "#{owner.name} Enterprise account"
    else
      "#{owner.display_login} account"
    end
  end
  helper_method :account_description
end
