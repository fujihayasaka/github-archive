# typed: true
# frozen_string_literal: true

class SponsorsPrimerMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include ApplicationHelper
  include ActionView::Helpers::DateHelper

  helper Primer::ViewHelper

  helper :avatar
  helper :bundle
  helper :mailer_bundle

  # Public: This is an arbitrary limit used to make sure we don't
  # send an email with a long list of sponsors. It can be modified if needed.
  GOAL_CONTRIBUTORS_LIMIT = 40
  SKIP_DATA_PROVISION_INVOICE_SPONSOR_LOGINS = %w(github microsoft).freeze
  STRIPE_W8_OR_W9_MIGRATION_DEADLINE_TEXT = Date.new(2022, 8, 31).strftime("%B %-d, %Y")
  INVOICE_BALANCE_SUPPORT_SUBJECT = "GitHub Sponsors: Invoice Balance"
  PAYPAL_DEPRECATION_DATE = Date.new(2023, 2, 23)
  PAYPAL_DEPRECATION_DATE_TEXT = PAYPAL_DEPRECATION_DATE.strftime("%B %-d, %Y")

  self.mailer_name = "mailers/sponsors_primer"
  layout "layouts/primer_layout"

  # Public: Sends an email to org admins and billing managers when an organization signs an invoiced agreement
  def send_signed_invoice_agreement(org:)
    @org = org
    @footer_links = default_footer_links

    premail(
      from: github_noreply,
      bcc: admin_emails(@org) | billing_emails(@org),
      subject: "GitHub Invoiced Agreement signed for @#{org}",
    )
  end

  # Public: Sends an email to org admins and billing managers when an organization fails at setting up invoiced agreement
  def invoiced_sponsors_setup_failure(org:)
    @org = org
    @footer_links = default_footer_links

    premail(
      from: github_noreply,
      bcc: admin_emails(@org) | billing_emails(@org),
      subject: "Setting up invoiced billing for GitHub Sponsors failed for @#{org}",
    )
  end

  # Public: Sends an email to org admins and billing managers when an organization successfully sets up invoiced agreement
  def invoiced_sponsors_setup_success(org:)
    @org = org
    @footer_links = default_footer_links

    premail(
      from: github_noreply,
      bcc: admin_emails(@org) | billing_emails(@org),
      subject: "@#{org} is now using invoiced billing for GitHub Sponsors",
    )
  end

  # Public: Sends an email to maintainer when sponsor upgrades their sponsorship
  #
  # sponsorable - the User or Organization being sponsored
  # sponsorship - the Sponsorship that was upgraded
  # tier - the sponsorship tier that the sponsor upgraded to
  def sponsorship_upgrade_notice(sponsorable:, sponsorship:, tier:)
    @sponsorable = sponsorable
    @sponsorship = sponsorship
    @tier = tier
    @footer_links = default_footer_links
    sponsor = @sponsorship.sponsor
    who_is_sponsorable = sponsor.organization? ? "@#{@sponsorable}'s" : "Your"
    @title = "#{who_is_sponsorable} sponsorship from @#{sponsor} was upgraded!"
    subject = "#{who_is_sponsorable} sponsorship from @#{sponsor} was upgraded on GitHub Sponsors!"
    premail(from: github_noreply, to: user_email(@sponsorable), subject: subject)
  end

  # Public: Communicate to org that their agreement signature has been terminated
  #
  # org: the Organization whose agreement signature was terminated
  # termination_date: the Date that the agreement signature was terminated
  def invoice_agreement_signature_terminated(org:, termination_date:)
    @org = org
    @termination_date = termination_date.strftime("%B %-d, %Y")
    @footer_links = default_footer_links
    @summary = "GitHub Sponsors invoice agreement terminated for @#{org}"
    to_emails = admin_emails(@org) | billing_emails(@org)
    premail(from: github_noreply, to: to_emails, subject: @summary)
  end

  def existing_sponsorship_fee_reminder_for_credit_card_orgs(org:)
    @org = org
    @summary = "Reminder: Changes to GitHub Sponsors Fees"
    @invoiced_billing_docs_url = "#{GitHub.help_url}/sponsors/sponsoring-open-source-contributors/paying-for-github-sponsors-by-invoice"
    @blog_post_url = "#{GitHub.blog_url}/2023-04-04-whats-new-with-github-sponsors"
    @beta_blog_post_url = "#{GitHub.blog_url}/2019-05-23-announcing-github-sponsors-a-new-way-to-contribute-to-open-source/"
    to_emails = admin_emails(@org) | billing_emails(@org)
    premail(from: github_noreply, to: to_emails, subject: @summary)
  end

  # Sent to the sponsorable when a sponsorship is cancelled
  def sponsorship_cancellation_notice(sponsors_activity:, sponsorable:)
    @sponsors_activity = sponsors_activity
    @sponsorable = sponsorable

    # Due to a sponsor unlinking their patreon account
    # Otherwise, it's due to a normal cancellation on patreon so the normal copy is fine
    @unlinked_sponsor = @sponsors_activity.patreon? && !@sponsors_activity.sponsors_patreon_user.present?

    subject = if @unlinked_sponsor
      "Changes to your sponsorship"
    else
      maintainer = @sponsors_activity.sponsorable.user? ? "you" : "@#{@sponsors_activity.sponsorable.display_login}"
      "@#{@sponsors_activity.sponsor.display_login} cancelled their sponsorship of #{maintainer} for " \
        "#{@sponsors_activity.sponsors_tier.name}"
    end

    @cancellation_date = @sponsors_activity.created_at.strftime("%B %-d, %Y")
    @footer_links = default_footer_links

    premail(from: github_noreply, to: @sponsorable.sponsors_listing_email, subject: subject)
  end

  # We can eventually remove this method once all the PayPal sponsors have had their sponsorships cancelled or they've
  # switched payment methods. See https://github.com/github/sponsors/issues/4655.
  def sponsors_cancelled_paypal_sponsorships_notice(sponsor:, sponsorships:)
    @sponsor = sponsor
    @footer_links = default_footer_links
    to_emails = if @sponsor.organization?
      admin_emails(@sponsor) | billing_emails(@sponsor)
    else
      user_email(@sponsor)
    end
    units = "sponsorship".pluralize(sponsorships.size)
    who_was_paying = @sponsor.user? ? "you were" : "@#{@sponsor} was"
    @summary = "We cancelled the #{units} #{who_was_paying} paying for with PayPal"
    subject = "GitHub Sponsors: #{@summary}"
    @update_payment_method_url = if @sponsor.organization?
      settings_org_billing_tab_url(organization_id: @sponsor, tab: "payment_information")
    else
      settings_user_billing_tab_url(tab: "payment_information")
    end
    @past_sponsorships_url = if @sponsor.organization?
      settings_org_billing_url(@sponsor, sponsorships_tab: "past", anchor: "sponsorship-history")
    else
      settings_user_billing_url(sponsorships_tab: "past", anchor: "sponsorship-history")
    end
    @sponsorships = sponsorships
    GitHub::PrefillAssociations.prefill_associations(@sponsorships, [:sponsorable, :tier])
    @changelog_url = "#{GitHub.blog_url}/changelog/2023-01-23-github-sponsors-will-stop-supporting-paypal/"
    premail(from: github_noreply, to: to_emails, subject: subject)
  end

  def sponsorships_export(sponsorable:, filename:, description:, mime_type:, export_content:, actor:)
    @sponsorable = sponsorable
    @description = description
    @actor = actor
    @footer_links = default_footer_links

    attachments[filename] = {
      mime_type: mime_type,
      content: export_content,
    }

    premail(
      from: github_noreply,
      to: sponsorable.sponsors_listing_email,
      subject: "Your GitHub Sponsors #{@description} sponsorships export is ready!",
    )
  end

  def sponsors_sponsorships_export(sponsor:, filename:, mime_type:, export_content:, actor:)
    @sponsor = sponsor
    @actor = actor
    @footer_links = default_footer_links

    attachments[filename] = {
      mime_type: mime_type,
      content: export_content,
    }

    premail(
      from: github_noreply,
      to: user_email(@actor),
      subject: "Your GitHub Sponsoring Sponsorships export is ready!",
    )
  end

  def sponsors_dependencies_export(filename:, mime_type:, export_content:, actor:)
    @actor = actor
    @footer_links = default_footer_links

    attachments[filename] = {
      mime_type: mime_type,
      content: export_content,
    }

    premail(
      from: github_noreply,
      to: user_email(@actor),
      subject: "Your GitHub Sponsoring Dependencies export is ready!",
    )
  end

  # Public: Communicate to sponsor that their sponsorship to the sponsorable is pending (unpaid).
  #
  # sponsorable - User or Organization being sponsored
  # sponsor - User or Organization sponsoring the maintainer
  # sponsorship_amount - String representing the amount of the sponsorship (e.g. $4)
  def pending_sponsorship(sponsorable:, sponsor:, sponsorship_amount:)
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsorship_amount = sponsorship_amount
    @footer_links = default_footer_links

    who_is_sponsoring = @sponsor.organization? ? "@#{@sponsor}'s" : "Your"

    @title = "#{who_is_sponsoring} sponsorship of @#{@sponsorable} is pending!"

    subject = "#{who_is_sponsoring} sponsorship of @#{@sponsorable} is pending on GitHub Sponsors!"

    recipient = @sponsor.organization? ? @sponsor.billing_email : user_email(@sponsor)

    premail(from: github_noreply, to: recipient, subject: subject)
  end

  # Public: Communicate to sponsor that their new sponsorship to the sponsorable was successful.
  #
  # sponsorable - User or Organization being sponsored
  # sponsor - User or Organization sponsoring the maintainer
  # sponsorship_amount - String representing the amount of the sponsorship (e.g. $4)
  # tier - SponsorsTier that the sponsorship is for
  # sponsor_next_billing_date - Date that the sponsor will be billed next
  # patreon - whether the sponsorship is via patreon or not
  def now_sponsoring(sponsorable:, sponsor:, sponsorship_amount:, tier:,
                     sponsor_next_billing_date:, patreon: false)
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsorship_amount = sponsorship_amount
    @tier = tier
    @repository = @tier.repository_for_sponsor(@sponsor)
    @recurring = tier.recurring?
    @sponsor_next_billing_date = sponsor_next_billing_date.strftime("%B %-d, %Y")
    @footer_links = default_footer_links
    @patreon = patreon

    who_is_sponsoring = if @sponsor.organization?
      "@#{@sponsor}"
    else
      "You"
    end
    verb = if @recurring
      @sponsor.organization? ? " is now sponsoring" : "'re now sponsoring"
    else
      " sponsored"
    end
    @title = "#{who_is_sponsoring}#{verb} @#{@sponsorable}!"

    subject = "#{who_is_sponsoring}#{verb} @#{@sponsorable} on GitHub Sponsors!"
    recipient = @sponsor.organization? ? @sponsor.billing_email : user_email(@sponsor)

    premail(from: github_noreply, to: recipient, subject: subject)
  end

  def patreon_now_sponsoring(sponsorable:, sponsor:)
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsor_noun = @sponsor.organization? ? "@#{@sponsor}" : "you"
    @footer_links = default_footer_links
    @patreon_url = @sponsorable.sponsors_patreon_membership_link
    @sponsoring_url = sponsors_view_sponsorships_url(@sponsor)

    who_is_sponsoring = @sponsor.organization? ? "@#{@sponsor}" : "You"
    verb = @sponsor.organization? ? " is now sponsoring" : "'re now sponsoring"

    subject = "#{who_is_sponsoring}#{verb} @#{@sponsorable} on GitHub Sponsors!"
    recipient = @sponsor.organization? ? @sponsor.billing_email : user_email(@sponsor)
    premail(from: github_noreply, to: recipient, subject: subject)
  end

  def patreon_new_sponsor(sponsor:, sponsorable:)
    @sponsorable = sponsorable
    @sponsor = sponsor
    listing = @sponsorable.sponsors_listing

    @sponsorable_descriptor = @sponsorable.user? ? "your" : "@#{@sponsorable}'s"

    @footer_links = default_footer_links

    who_has_a_new_sponsor = if @sponsorable.organization?
      "@#{@sponsorable} has"
    else
      "You have"
    end
    subject = "#{who_has_a_new_sponsor} a new sponsor on GitHub Sponsors (@#{@sponsor.display_login})!"

    premail(from: github_noreply, to: listing.contact_email_address, subject: subject)
  end

  # Sent to the sponsorable when a pledge is deleted on Patreon
  def patreon_cancellation(sponsorable:, sponsor:)
    @sponsor = sponsor
    @sponsorable = sponsorable

    subject = "Changes to your sponsorship"
    @footer_links = default_footer_links
    premail(from: github_noreply, to: user_email(sponsorable), subject: subject)
  end

  # Public: Communicate to sponsor that their new bulk sponsorship was successful.
  #   Includes CSV attachment with "Maintainer username" and "Sponsorship amount in USD" of the new sponsorships.
  #
  # sponsor - User or Organization doing the sponsoring
  # total_amount - String representing the total amount of the bulk sponsorship (e.g. $4)
  # is_recurring - Boolean indicating if the sponsorships are recurring
  # sponsorship_count - Integer of number of sponsorships created
  # any_sponsored_users - Boolean indicating if any of the sponsorships were for users
  # any_sponsored_organizations - Boolean indicating if any of the sponsorships were for organizations
  # filename - String of the filename for the CSV attachment containing the new sponsorships
  # export_content - String of the CSV attachment containing the new sponsorships
  sig do
    params(
      sponsor: GitHubSponsors::Types::Sponsor,
      total_amount: String,
      sponsorship_count: Integer,
      any_sponsored_users: T::Boolean,
      any_sponsored_organizations: T::Boolean,
      filename: String,
      export_content: String,
      is_recurring: T::Boolean,
    ).void
  end
  def now_sponsoring_via_bulk_sponsorship(sponsor:, total_amount:, sponsorship_count:, any_sponsored_users:,
    any_sponsored_organizations:, filename:, export_content:, is_recurring: false)
    @sponsor = sponsor
    @view_sponsorships_url = sponsors_view_sponsorships_url(@sponsor)
    @footer_links = default_footer_links
    @title = "You contributed a total of #{total_amount} "
    if is_recurring
      @title += "a month "
    end
    @title += "to "
    @title += sponsoring_users_and_organizations_text(
      sponsorship_count: sponsorship_count,
      any_sponsored_users: any_sponsored_users,
      any_sponsored_organizations: any_sponsored_organizations,
    ) + "!"

    attachments[filename] = {
      mime_type: "text/csv",
      content: export_content,
    }

    subject = "You're now sponsoring multiple maintainers on GitHub Sponsors!"
    recipient = @sponsor.organization? ? @sponsor.billing_email : user_email(@sponsor)
    premail(from: github_noreply, to: recipient, subject: subject)
  end

  def sponsorable_no_longer_sponsorable(sponsorable:, sponsor:, tier:)
    sponsorable_email = user_email(sponsorable, allow_private: false) if sponsorable.user?
    sponsorable_email ||= github_noreply(sponsorable)
    to_address = if sponsor.user?
      user_email(sponsor)
    else
      []
    end
    bcc_addresses = if sponsor.organization?
      admin_emails(sponsor)
    else
      []
    end

    @subject = "@#{sponsorable} is no longer available to sponsor in GitHub Sponsors"
    @footer_links = default_footer_links
    @sponsorable = sponsorable
    @sponsor = sponsor
    @tier = tier
    @sponsors_view_sponsorships_url = sponsors_view_sponsorships_url(@sponsor)

    premail(
      from: github_noreply(sponsorable),
      reply_to: sponsorable_email,
      to: to_address,
      bcc: bcc_addresses,
      subject: @subject,
    )
  end

  def approval_request_submitted(sponsorable:)
    subject = "Your GitHub Sponsors profile has been submitted for review"
    recipients = listing_admin_recipients(sponsorable)
    @footer_links = default_footer_links
    @sponsorable = sponsorable
    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: subject,
    )
  end

  # Public: Send waitlist acceptance message
  #
  # sponsorsable - User/Org accepted into Sponsors
  # extra_info - optional String that will be displayed below the message header
  def waitlist_acceptance(sponsorable:, extra_info: nil)
    who_was_accepted = if sponsorable.organization?
      "@#{sponsorable} is"
    else
      "You're"
    end
    subject = "#{who_was_accepted} in! Welcome to GitHub Sponsors 💖"
    contact_email = sponsorable.sponsors_listing_email

    @sponsorable = sponsorable
    @listing = sponsorable.sponsors_listing
    @is_user = sponsorable.user?
    @footer_links = default_footer_links
    @extra_info = extra_info
    @signup_url = sponsorable_signup_url(@sponsorable)

    premail(from: github_noreply, to: contact_email, subject: subject)
  end

  # Public: A reminder message to be sent 30 days after signing up for Sponsors.
  def first_profile_setup_reminder(sponsorable:)
    subject = "Finish setting up your GitHub Sponsors Profile"
    contact_email = sponsorable.sponsors_listing_email

    @sponsorable = sponsorable
    @listing = sponsorable.sponsors_listing
    @is_user = sponsorable.user?
    @footer_links = default_footer_links
    @signup_url = sponsorable_signup_url(@sponsorable)

    premail(from: github_noreply, to: contact_email, subject: subject)
  end

  # Public: A reminder message to be sent one week before the matching period starts,
  # which is about 7 weeks after the sponsorable signed up for Sponsors.
  def second_profile_setup_reminder(sponsorable:)
    subject = "Don't forget to set up your GitHub Sponsors profile"
    contact_email = sponsorable.sponsors_listing_email

    @sponsorable = sponsorable
    @listing = sponsorable.sponsors_listing
    @is_user = sponsorable.user?
    @footer_links = default_footer_links
    @signup_url = sponsorable_signup_url(@sponsorable)

    premail(from: github_noreply, to: contact_email, subject: subject)
  end

  # Public: A message to be sent only to previously accepted users (i.e., those who were moved off the Sponsors waitlist) who
  # haven't submitted their Sponsors profile for review.
  def submitted_your_profile_reminder(sponsorable:)
    subject = "Finish setting up your GitHub Sponsors profile to take advantage of the Matching Fund"
    contact_email = sponsorable.sponsors_listing_email

    @sponsorable = sponsorable
    @listing = sponsorable.sponsors_listing
    @is_user = sponsorable.user?
    @footer_links = default_footer_links

    premail(from: github_noreply, to: contact_email, subject: subject)
  end

  def waitlist_confirmation(sponsorable:, waitlist_title:)
    who_is_on_the_waitlist = if sponsorable.organization?
      "@#{sponsorable} is"
    else
      "You're"
    end
    @subject = "#{who_is_on_the_waitlist} on the #{waitlist_title}"

    contact_email = sponsorable.sponsors_listing_email

    @waitlist_title = waitlist_title
    @types = if sponsorable.user?
      "developers"
    elsif sponsorable.organization?
      "organizations"
    end
    @footer_links = default_footer_links

    premail(from: github_opensource, to: contact_email, subject: @subject)
  end

  def goal_completed(goal:)
    @goal = goal
    @sponsorable = @goal.listing.sponsorable
    @contributions_count = @goal.contributions.count
    @sponsors = @goal
      .contributions
      .preload(:sponsor)
      .limit(GOAL_CONTRIBUTORS_LIMIT)
      .map(&:sponsor)
    @footer_links = default_footer_links

    subject = if @sponsorable.organization?
      "@#{@sponsorable} has reached its GitHub Sponsors goal!"
    else
      "You reached your GitHub Sponsors goal!"
    end

    premail(
      from: github_noreply,
      to: @sponsorable.sponsors_listing_email,
      subject: subject,
    )
  end

  def reached_match_cap(sponsorable:)
    @sponsorable_login = sponsorable.display_login
    @match_limit = Billing::Money.new(SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS)
                                 .format(no_cents: true)
    @sponsorships_plus_match = Billing::Money.new(SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS * 2)
                                             .format(no_cents: true)
    @footer_links = default_footer_links

    premail(
      from: github_noreply,
      to: sponsorable.sponsors_listing_email,
      subject: "Wow, you've received #{@match_limit} in GitHub Sponsors sponsorships!",
    )
  end

  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable).void }
  def listing_approved(sponsorable:)
    @sponsorable = sponsorable
    this_listing = sponsorable.sponsors_listing

    # If the sponsorable has somehow deleted their profile before this
    # mailer was proceessed, bail out early.
    return unless this_listing.present?

    @listing = this_listing
    recipients = listing_admin_recipients(sponsorable)

    who_was_approved = @sponsorable.organization? ? "@#{@sponsorable}'s" : "Your"
    @subject = "#{who_was_approved} GitHub Sponsors profile is live"

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: @subject,
    )
  end

  # recipient - the User who should receive the email
  # filename - String name of the file attachment
  # mime_type - String mime type for the file attachment
  # export_content - contents of the file attachment, as a String
  # org - optional Organization whose results are represented in the given export content, or nil if the export is for
  #       the recipient
  # explore_params - Hash of String URL parameters for use in linking the recipient back to the Explore Sponsors page
  #                  with the same filters as the export
  def sponsorable_maintainers_export(recipient:, filename:, mime_type:, export_content:, org:, explore_params:)
    @recipient = recipient
    @org = org
    @explore_params = explore_params
    @whose_export = @org ? "@#{@org}'s" : "Your"
    @sponsor = @org || @recipient

    attachments[filename] = {
      mime_type: mime_type,
      content: export_content,
    }

    premail(
      from: github_noreply,
      to: user_email(@recipient),
      subject: "#{@whose_export} GitHub Explore Sponsors results export is ready",
    )
  end

  # sponsorable - Organization that has a SponsorsListing marked as a fiscal host
  # filename - String name of the file for the attachment
  # export_content - String content of the file to attach to the email
  # actor - optional User who requested the export
  # recipient - optional User who should receive the email; defaults to the sponsorable if omitted
  def payouts_export(sponsorable:, filename:, export_content:, actor: nil, recipient: nil)
    @sponsorable = sponsorable
    @actor = actor
    @footer_links = default_footer_links
    contact_email = if recipient
      user_email(recipient)
    else
      @sponsorable.sponsors_listing_email
    end
    @recipient = recipient || @sponsorable

    attachments[filename] = {
      mime_type: "text/csv",
      content: export_content,
    }

    @whose_export = if @sponsorable.organization? || @recipient != @sponsorable
      "@#{@sponsorable}'s"
    else
      "Your"
    end

    excitement = if @recipient == @sponsorable
      "!"
    end

    premail(
      from: github_noreply,
      to: contact_email,
      subject: "#{@whose_export} payouts export for GitHub Sponsors is ready#{excitement}",
    )
  end

  def sponsors_transactions_export(sponsorable:, filename:, mime_type:, export_content:, description:, actor: nil, recipient: nil)
    @sponsorable = sponsorable
    @description = description
    @footer_links = default_footer_links
    @actor = actor
    to_address = if recipient
      user_email(recipient)
    else
      @sponsorable.sponsors_listing_email
    end
    @recipient = recipient || sponsorable

    attachments[filename] = {
      mime_type: mime_type,
      content: export_content,
    }

    whose_export = if @sponsorable.organization? || @recipient != @sponsorable
      "@#{@sponsorable}'s"
    else
      "Your"
    end

    excitement = if @recipient == @sponsorable
      "!"
    end

    premail(
      from: github_noreply,
      to: to_address,
      subject: "#{whose_export} GitHub Sponsors transactions export for #{@description} is ready#{excitement}",
    )
  end

  def milestone_reached(sponsorable:, milestone_title:)
    @sponsorable = sponsorable
    @milestone_title = milestone_title

    who_reached_milestone = if @sponsorable.organization?
      "@#{@sponsorable} has"
    else
      "You've"
    end

    premail(
      from: github_noreply,
      to: sponsorable.sponsors_listing_email,
      subject: "#{who_reached_milestone} reached a milestone!",
    )
  end

  # Public: send an email to the maintainer regarding the new sponsorship
  #
  # sponsorship - Sponsorship record
  # tier_paid - optional SponsorsTier, used for concurrent one-time payments where tier differs from Sponsorship record
  def new_sponsor(sponsorship, tier_paid: nil)
    @sponsorship = sponsorship
    @sponsorable = sponsorship.sponsorable
    @sponsor = sponsorship.sponsor
    listing = @sponsorable.sponsors_listing

    @sponsorable_descriptor = @sponsorable.user? ? "you" : "@#{@sponsorable}"
    @private_sponsorship_descriptor = @sponsorable.user? ? "you" : "members of @#{@sponsorable}"
    @sponsorship_amount_cycle = if sponsorship.concurrent_payment?(tier_paid: tier_paid)
      tier_paid.name
    else
      sponsorship.amount_per_cycle
    end

    @is_first_sponsorship = @sponsorship.first_for?(sponsorable: @sponsorable)
    @needs_tax_form = needs_tax_form?(listing)
    @next_payout_date = listing.next_payout_date_formatted
    @on_payout_probation = listing.on_payout_probation?
    @automated_payouts_disabled = listing.stripe_automated_payouts_disabled?
    @sponsor_note = @sponsorship.new_sponsor_email_note
    @footer_links = default_footer_links
    @via_bulk_sponsorship = @sponsorship.via_bulk_sponsorship?

    who_has_a_new_sponsor = if @sponsorable.organization?
      "@#{@sponsorable} has"
    else
      "You have"
    end
    subject = "#{who_has_a_new_sponsor} a new #{"private " if @sponsorship.privacy_private?}" \
              "#{@sponsorship_amount_cycle} sponsor on GitHub Sponsors " \
              "(@#{@sponsor.display_login})!"

    premail(from: github_noreply, to: listing.contact_email_address, subject: subject)
  end

  def needs_tax_form?(listing)
    !listing.uses_fiscal_host? && !listing.stripe_w8_or_w9_verified?
  end

  def redrafted_due_to_missing_tax_form(sponsorable:)
    @login = sponsorable.display_login
    @footer_links = default_footer_links

    recipients = listing_admin_recipients(sponsorable)
    whose_listing = if sponsorable.organization?
      "@#{sponsorable}'s"
    else
      "Your"
    end

    premail(
      from: github_noreply,
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: "#{whose_listing} GitHub Sponsors profile has been unpublished until we collect your tax form",
    )
  end

  def low_credit_balance_warning(sponsor:, zero_balance_date:)
    return unless sponsor.sponsors_invoiced? && zero_balance_date.present?
    return if sponsor.feature_enabled?(:sponsors_disable_low_credit_balance_warning_email)

    zero_balance_distance = distance_of_time_in_words_to_now(zero_balance_date)
    @sponsor = sponsor
    @zero_balance_date_formatted = zero_balance_date.strftime("%B %-d, %Y")
    @summary = "@#{sponsor}'s sponsorship balance will run out in #{zero_balance_distance}"
    subject = "GitHub Sponsors: #{@summary}"
    @new_invoice_url = new_org_sponsoring_invoice_url(@sponsor)

    premail(
      from: github_noreply,
      to: (admin_emails(sponsor) | billing_emails(sponsor)),
      subject: subject,
    )
  end

  def credit_balance_increase_notification(sponsor:)
    return unless sponsor.sponsors_invoiced?

    @sponsor = sponsor
    @summary = "Funds added to @#{sponsor}'s account for sponsorships"

    subject = "GitHub Sponsors: #{@summary}"

    premail(
      from: github_noreply,
      to: admin_emails(sponsor) | billing_emails(sponsor),
      bcc: [GitHub.accounts_receivable_email],
      subject: subject,
    )
  end

  def sponsorship_permission_granted(organization:, enterprise:)
    @organization = organization
    @enterprise = enterprise

    @summary = "You've been granted permission to create sponsorships."

    subject = "GitHub Sponsors: #{@summary}"

    premail(
      from: github_noreply,
      to: admin_emails(organization) | billing_emails(organization),
      subject: subject
    )
  end

  def sponsorship_permission_revoked(organization:, enterprise:)
    @organization = organization
    @enterprise = enterprise

    @summary = "Your sponsorship permission has been rescinded."

    subject = "GitHub Sponsors: #{@summary}"

    premail(
      from: github_noreply,
      to: admin_emails(organization) | billing_emails(organization),
      subject: subject
    )
  end

  # Public: Notify the sponsorable a transaction to their Stripe account has been reversed.
  sig do
    params(
      sponsor: GitHubSponsors::Types::Sponsor,
      sponsorable: GitHubSponsors::Types::Sponsorable,
      stripe_account: Billing::StripeConnect::Account
    ).returns(String)
  end
  def transaction_reversal(sponsor:, sponsorable:, stripe_account:)
    @sponsorable = sponsorable
    @sponsor = sponsor
    @stripe_account = stripe_account

    @summary = "Notification of transaction reversal"

    subject = "GitHub Sponsors: #{@summary}"

    premail(
      from: github_noreply,
      to: sponsorable.sponsors_listing_email,
      subject: subject
    )
  end

  private

  # Private: Returns text describing the group of sponsors depending on the number of sponsorship and who the
  #   sponsorables are.
  #
  # sponsorship_count - An Integer representing the number of sponsorships
  # any_sponsored_users - Boolean representing whether any of the sponsorables are users
  # any_sponsored_organizations - Boolean representing whether any of the sponsorables are organizations
  #
  # Returns a String
  def sponsoring_users_and_organizations_text(sponsorship_count:, any_sponsored_users:, any_sponsored_organizations:)
    text = "#{sponsorship_count} "
    text += if any_sponsored_organizations && any_sponsored_users
      "maintainer".pluralize(sponsorship_count) + " and " + "organization".pluralize(sponsorship_count)
    elsif any_sponsored_organizations
      "organization".pluralize(sponsorship_count)
    else
      "maintainer".pluralize(sponsorship_count)
    end
  end

  # Private: Get the URL to the User or Organization profile's sponsoring tab.
  #
  # Returns a String
  def sponsors_view_sponsorships_url(sponsor)
    if sponsor.is_a?(Organization)
      UrlHelpers.org_sponsoring_url(sponsor, protocol: GitHub.dotcom_host_protocol, host: GitHub.dotcom_host_name)
    else
      user_sponsoring_url = UrlHelpers.user_url(
        sponsor,
        protocol: GitHub.dotcom_host_protocol,
        host: GitHub.dotcom_host_name
      )
      "#{user_sponsoring_url}?tab=sponsoring"
    end
  end

  def default_footer_links
    [
      { url: settings_email_preferences_url, text: "Email preferences" },
      { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
      { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" },
      { url: login_url, text: "Sign in to GitHub" },
    ]
  end

  def listing_admin_recipients(sponsorable)
    sponsorable_contact = sponsorable.sponsors_listing_email

    if sponsorable.organization?
      recipients = user_or_admin_recipients(sponsorable)
      recipients[:bcc] << sponsorable_contact
      recipients
    else
      {
        to: sponsorable_contact,
        bcc: [],
      }
    end
  end

  def include_data_provision_invoice?
    true unless @sponsor.display_login.in?(SKIP_DATA_PROVISION_INVOICE_SPONSOR_LOGINS)
  end
end
