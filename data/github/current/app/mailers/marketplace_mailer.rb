# typed: true
# frozen_string_literal: true

class MarketplaceMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/marketplace"

  layout "layouts/marketplace_mailer"

  def state_changed(action:, old_state:, new_state:, listing:, message:)
    subject = "#{listing.name} is now #{new_state}"

    @action = action
    @old_state = old_state
    @new_state = new_state
    @listing = listing
    @message = message

    mail(from: github_marketplace, to: "marketplace@github.com", subject: subject)
  end

  def listing_approved(user:, listing:, message: nil)
    @listing = listing
    @message = message

    mail(from: github_marketplace,
          to: user_email(user),
          subject: "#{listing.name} has been approved for the GitHub Marketplace")
  end

  def listing_redrafted(user:, new_state:, listing:, message: nil)
    subject = "#{listing.name} requires edits for the GitHub Marketplace"

    @listing = listing
    @new_state = new_state
    @message = message

    mail(from: github_marketplace, to: user_email(user), subject: subject)
  end

  def listing_delisted(user:, listing:, message: nil)
    subject = "#{listing.name} has been removed from the GitHub Marketplace"

    @listing = listing
    @message = message

    mail(from: github_marketplace, to: user_email(user), subject: subject)
  end

  def listing_subscriptions_cancelled(user:, listing:, date:, plan_name:)
    subject = "#{listing.name} Subscription Cancellation"

    @listing = listing
    @date = date
    @plan_name = plan_name

    mail(from: github_marketplace, to: user_email(user, user&.organization_billing_email), subject: subject)
  end

  def listing_rejected(user:, listing:, message: nil)
    subject = "#{listing.name} has been rejected for the GitHub Marketplace"

    @listing = listing
    @message = message

    mail(from: github_marketplace, to: user_email(user), subject: subject)
  end

  def retarget(user, previews, unsubscribe_token)
    @email_title = "Complete your GitHub Marketplace orders"
    @user = user
    @previews = previews
    @unsubscribe_token = unsubscribe_token

    mail(from: github_marketplace, to: user_email(user), subject: "Complete your GitHub Marketplace orders", categories: "marketplace, marketplace-retarget")
  end

  def featured_customers_need_review(listing:)
    @listing = listing
    @featured_org_logins = Organization.where(id: @listing.featured_organizations.where(approved: false).pluck(:organization_id)).pluck(:login)

    mail(from: github_marketplace, to: github_marketplace, subject: "Review: featured customers submitted for #{listing.name}", bcc: "india-marketplace-team@github.com", categories: "marketplace")
  end

  def creator_verification_update(to:, publisher_name:, verified:, reason:, custom_reason:, removing:)
    @publisher_name = publisher_name
    @verified = verified
    @reason = reason
    @custom_reason = custom_reason
    subject = "Publisher Verification for GitHub Marketplace - #{@publisher_name}"
    mail(from: github_marketplace, to: to, subject: subject, bcc: "india-marketplace-team@github.com")
  end

  def financial_onboarding_update(to:, cc:, listing_name:)
    @listing_name = listing_name
    subject = "GitHub Marketplace Application Onboarding - #{@listing_name}"
    mail(from: github_marketplace, to: to, subject: subject, cc: cc, bcc: "india-marketplace-team@github.com")
  end
end
