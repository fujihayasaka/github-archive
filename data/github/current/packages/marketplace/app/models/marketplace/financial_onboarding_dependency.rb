# typed: true
# frozen_string_literal: true

module Marketplace::FinancialOnboardingDependency
  FINANCIAL_ONBOARDING_REPO_NAME = "marketplace"
  FINANCIAL_ONBOARDING_SERVICE_BOT = "Marketplace-Bot"
  FINANCIAL_ONBOARDING_DRAFT_ISSUE_NUMBER = 2159
  FINANCIAL_ONBOARDING_UNVERIFIED_ISSUE_NUMBER = 2161
  PENDING_FROM_DRAFT_TEMPLATE_NAME = "onboard-paid-app-pending-from-draft.md"
  PENDING_FROM_UNVERIFIED_TEMPLATE_NAME = "onboard-paid-app-pending-from-unverified.md"

  LISTING_STATE = {
    unverified_listing: "unverified_listing",
    new_listing: "new_listing",
    spammy_listing: "notify_spammy_listing"
  }

  # Public: Calls financial onboarding functions. Creates issue and enqueues Financial Onboarding Job
  # listing_type - type of listing, either LISTING_STATE[:new_listing] or LISTING_STATE[:unverified_listing]
  # listing_name - name of the marketplace listing
  # listing_slug - slug of the marketplace listing
  # mailer_params - parameters used to sending financial onboarding email to user. Contains name, finance email and technical email of listing
  def initiate_financial_onboarding(listing_type, listing_name, listing_slug, mailer_params)
    created_issue_id = create_issue_in_marketplace(listing_type, listing_name, listing_slug)
    if created_issue_id
      FinancialOnboardingJob.perform_later(T.unsafe(self).webhook, created_issue_id, listing_type, mailer_params)
    end
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
      @user = User.find_by_login(FINANCIAL_ONBOARDING_SERVICE_BOT)
    end

    issue_template = create_issue_from_state(listing_type, listing_name, listing_slug, repo.id)
    if issue_template.is_a? Hash # if issue_template is a hash, it means it is a template issue
      handle_create_issue(@user, repo, issue_template)
    else # if issue_template is not a hash, it means it is a issue template name
      template_name = issue_template
      @issue_data = repo.issue_templates[template_name]

      if @issue_data.nil?
        GitHub.logger.info("Marketplace issue template not found", "code.function" => "create_issue_in_marketplace")
        return
      end
      # create issue template object, and change "[APP NAME]" from title to the actual app name, as well as adding Application Name and Biztools link to template body.
      title = @issue_data.title.gsub("[App Name]", listing_name)
      new_issue_body_with_link = @issue_data.body.gsub("**Biztool link** - ", "**Biztool link** - https://admin.github.com/biztools/marketplace/#{listing_slug}")
      new_issue_body = new_issue_body_with_link.gsub("Application Name -", "Application Name - #{listing_name}")
      @issue_template = {
        title: title,
        body: new_issue_body
      }

      handle_create_issue(@user, repo, @issue_template)
    end
  end

  # # Creates issue with provided user, repo and conditional template data and handles/logs error if issue creation fails
  def handle_create_issue(user, repo, template)
    if !template
      return
    end

    result = Issues.domain.create(
      Issues::CreateIssueAttributes.new(
        title: template[:title],
        body: template[:body],
        repository: repo,
      ),
      user,
    )

    case result
    when GH::Result::Ok
      result.value.id
    when GH::Result::Error
      GitHub.logger.info("Issue creation failed", "code.function" => "create_issue_from_state")
      nil
    end
  end

  # # Public: Replaces [APPNAME] and [APPSLUG] with listing name and listing slug respectively in input text
  # # Returns updated text after replacement
  def update_issue_content(content, listing_name, listing_slug)
    updated_content = content.gsub("[APPNAME]", listing_name)
    updated_content = updated_content.gsub("[APPSLUG]", listing_slug)
    updated_content
  end

  # Public: Finds a template issue in github/marketplace repository
  # Returns template issue if issue is found. If issue is not found, logs error before returning
  def find_template_issue(listing_type, repository_id)
    if listing_type == LISTING_STATE[:new_listing]
      template_issue = PENDING_FROM_DRAFT_TEMPLATE_NAME
    elsif listing_type == LISTING_STATE[:unverified_listing]
      template_issue = PENDING_FROM_UNVERIFIED_TEMPLATE_NAME
    elsif listing_type == LISTING_STATE[:notify_spammy_list]
      if Rails.env.development? || Rails.env.test?
        template_issue = Issue.where("number = '162' AND repository_id = #{repository_id}").first
      else
        template_issue = Issue.where("number = #{Marketplace::NotifySpammyList::DELIST_SPAMMY_LISTING_ISSUE_NUMBER} AND repository_id = #{repository_id}").first
      end
    end
    if !template_issue
      GitHub.logger.info("Template issue was not found", "code.function" => "find_template_issue")
      return
    end
    template_issue
  end

  # Public: Creates issue title and body on the basis of listing type
  # Returns issue template containing issue title and body
  def create_issue_from_state(listing_type, listing_name, listing_slug, repository_id)
    template_issue = find_template_issue(listing_type, repository_id)
    if template_issue == LISTING_STATE[:notify_spammy_list]
      if !template_issue
        return
      end

      issue_template = {
        title: update_issue_content(template_issue.title, listing_name, listing_slug),
        body: update_issue_content(template_issue.body,  listing_name, listing_slug)
      }
      issue_template
    else
      template_issue
    end
  end

  # Public: Finds github/marketplace repository
  # Returns repository if found
  def find_repository
    return unless org = Organization.find_by_login("github")
    repo = org.find_repo_by_name(FINANCIAL_ONBOARDING_REPO_NAME)
    repo if repo&.private?
  end
end
