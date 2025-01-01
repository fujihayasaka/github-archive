# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class FinancialOnboardingJob < ApplicationJob
  queue_as :marketplace
  retry_on_dirty_exit
  include Marketplace::FinancialOnboardingDependency
  include HookDeliveriesHelper

  # Public: Runs Financial Onboarding Job for a particular marketplace listing
  # hook - webhook associated with the current marketplace listing
  # issue_id - ID of the issue created for the current marketplace listing
  # listing_type - type of listing, either LISTING_STATE[:new_listing] or LISTING_STATE[:unverified_listing]
  # mailer_params - parameters used to sending financial onboarding email to user. Contains name, finance email and technical email of listing
  def perform(hook, issue_id, listing_type, mailer_params)
    issue = Issue.find_by(id: issue_id)

    deliveries = get_webhook_deliveries(hook, mailer_params[:listing_name])
    if !deliveries
      update_issue_with_fail(issue)
      return
    end
    is_check_successful = is_webhook_check_successful(deliveries)
    if is_check_successful
      send_email_for_financial_onboarding(mailer_params[:finance_email], mailer_params[:technical_email], mailer_params[:listing_name])

      update_issue_with_success(issue, listing_type)
    else
      update_issue_with_fail(issue)
    end
  end

  # Public: Get deliveries for given hook
  # Logs error with listing details if hook or hookshot is not found
  # Returns an array of webhook deliveries
  def get_webhook_deliveries(hook, listing_name)
    T.bind(self, T.untyped)
    @current_hook ||= Hook.find_by(id: hook.id)
    if !@current_hook
      GitHub.logger.info("Webhook deliveries could not be fetched", { "code.namespace" => "FinancialOnboardingJob", "code.function" => "get_webhook_deliveries", "gh.marketplace.hook_id" => hook_id, "gh.marketplace.listing.name" => listing_name })
      return
    end
    @hookshot = Hookshot::Client.for_parent current_hook.hookshot_parent_id
    if !@hookshot
      GitHub.logger.info("Webhook deliveries could not be fetched", { "code.namespace" => "FinancialOnboardingJob", "code.function" => "get_webhook_deliveries", "gh.marketplace.hook_id" => hook_id, "gh.marketplace.listing.name" => listing_name })
      return
    end
    params_for_search = { limit: 15 }
    status, data = hookshot.deliveries_for_hook(current_hook.id, params_for_search)
    deliveries = data["deliveries"].present? ? Hookshot::Delivery.load(data["deliveries"]) : []
    deliveries
  end

  # Public: Updates issue when webhook check is successful
  #  - Adds a comment to the issue stating webhook check was successful
  #  - Adds form-sent label to issue
  #  - Updates tasklist in issue description to mark required tasks as completed
  def update_issue_with_success(issue, listing_type)
    T.bind(self, T.untyped)
    comment_body = "Webhook check was successful. Financial onboarding google form has been sent to the user"
    update_issue(issue, comment_body)
    with_write { add_label(issue, "form-sent", "Financial Onboarding google form sent") }
    if listing_type == LISTING_STATE[:new_listing]
      webhook_check_operation = '{"operation":"check","position":[1,0],"checked":true}'
      form_sent_check_operation = '{"operation":"check","position":[2,1],"checked":true}'
    elsif listing_type == LISTING_STATE[:unverified_listing]
      webhook_check_operation = '{"operation":"check","position":[0,0],"checked":true}'
      form_sent_check_operation = '{"operation":"check","position":[1,1],"checked":true}'
    end
    perform_tasklist_operation(webhook_check_operation, issue)
    perform_tasklist_operation(form_sent_check_operation, issue)
  end

  # Public: Marks a particular task as completed in tasklist in the issue description
  # Logs error if tasklist operation is unsuccessful
  def perform_tasklist_operation(task_list_operation, issue)
    if operation = TaskListOperation.from(task_list_operation)
      text = operation.call(issue.body)
      if text
        with_write do
          issue.body = text
          if !issue.save
            GitHub.logger.info("Tasklist check operation failed", { "code.namespace" => "FinancialOnboardingJob", "code.function" => "perform_tasklist_operation", "gh.issue.number" => issue.number })
          end
        end
      else
        GitHub.logger.info("Tasklist check operation failed", { "code.namespace" => "FinancialOnboardingJob", "code.function" => "perform_tasklist_operation", "gh.issue.number" => issue.number })
      end
    end
  end

  # Public: Updates issue when webhook check is unsuccessful
  # Adds a comment to the issue stating webhook check was unsuccessful
  def update_issue_with_fail(issue)
    comment_body = "Webhook check was unsuccessful. Please manually send the financial onboarding google form to the user"
    update_issue(issue, comment_body)
  end

  # Public: Adds a comment to the given issue
  # Uses the Marketplace-Bot account to create the comment on issue
  def update_issue(issue, comment_body)
    if Rails.env.development?
      @user = User.find_by_login("monalisa")
    else
      @user = User.find_by_login("Marketplace-Bot")
    end
    @comment = with_write { issue.create_comment(@user, comment_body) }
  end

  # Public: Checks if lastest webhook delivery was successful
  def is_webhook_check_successful(deliveries)
    deliveries = deliveries.sort_by &:delivered_at
    if deliveries.last.status_code == 200
      true
    else
      false
    end
  end

  # Public: Sends email to listing technical and financial email ids
  # Uses MarketplaceMailer to send financial onboarding update email containing onboarding google form
  def send_email_for_financial_onboarding(sender_email, cc_email, listing_name)
    mailer_params = { to: sender_email, cc: cc_email, listing_name: listing_name }
    MarketplaceMailer.financial_onboarding_update(**mailer_params).deliver_later if mailer_params
  end
end
