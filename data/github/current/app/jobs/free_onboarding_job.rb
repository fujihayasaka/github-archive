# typed: true
# frozen_string_literal: true

class FreeOnboardingJob < ApplicationJob
  ONBOARDING_REPO_NAME = "marketplace"
  ONBOARDING_SERVICE_BOT = "Marketplace-Bot"
  TEMPLATE_NAME = "onboard-free-app-unverified-pending.md"

  queue_as :marketplace
  include Marketplace::FreeOnboardingDependency
  include HookDeliveriesHelper

  def self.enabled?
    GitHub.marketplace_enabled? && GitHub.flipper[:marketplace_create_free_app_verification_onboarding_issues].enabled?
  end

  # Public: Runs Financial Onboarding Job for a particular marketplace listing
  # hook - webhook associated with the current marketplace listing
  # issue_id - ID of the issue created for the current marketplace listing
  # listing_type - type of listing, either LISTING_STATE[:new_listing] or LISTING_STATE[:unverified_listing]
  # mailer_params - parameters used to sending financial onboarding email to user. Contains name, finance email and technical email of listing
  def perform(listing_type, listing_name, listing_slug)
    create_issue_in_marketplace(listing_type, listing_name, listing_slug)
  end

  # Public: Creates issue in github/marketplace repository
  # Returns issue_id if issue is successfully created. If issue is not successfully created, logs error before returning

  def create_issue_in_marketplace(listing_type, listing_name, listing_slug)
    repo = self.find_repository

    if !repo
      GitHub.logger.info("Marketplace repository was not found", "code.function" => "create_issue_in_marketplace")
      return
    end

    if Rails.env.development?
      @user = User.find_by_login("monalisa")
    else
      @user = User.find_by_login(ONBOARDING_SERVICE_BOT)
    end

    @issue_data = repo.issue_templates[TEMPLATE_NAME]

    # create issue template object, and change "[APP NAME]" from title to the actual app name, as well as adding Application Name and Biztools link to template body.
    title = @issue_data.title.gsub("[App Name]", listing_name)

    new_issue_body_with_link = @issue_data.body.gsub("**Biztool link** - ", "**Biztool link** - https://admin.github.com/biztools/marketplace/#{listing_slug}")
    new_issue_body = new_issue_body_with_link.gsub("Application Name -", "Application Name - #{listing_name}")

    @issue_template = {
      title: title,
      body: new_issue_body
    }

    if !@issue_template
      return
    end

    @issue = Issue::Builder.new(@user, repo).build({ issue: @issue_template })

    if with_write { @issue.save }
      @issue.id
    else
      # notify marketplace team issue creation failed, slack push to a particular channel
      GitHub.logger.info("Issue creation failed", "code.function" => "create_issue_from_state")
      nil
    end
  end

  # Public: Finds github/marketplace repository
  # Returns repository if found
  def find_repository
    return unless org = Organization.find_by_login("github")
    repo = org.org_repositories.find_by(name: ONBOARDING_REPO_NAME)
    return repo if repo&.private?
  end
end
