# typed: true
# frozen_string_literal: true

require "github/config/mailchimp"

module GitHub
  # An overview of the MailChimp service integration can be found here:
  # https://github.com/github/githubber-content/blob/master/docs/technology/dotcom/email/marketing-mail.md
  class Mailchimp
    autoload :MailchimpError, "github/mailchimp/mailchimp_error"
    autoload :Error, "github/mailchimp/error"
    autoload :WebhookError, "github/mailchimp/webhook_error"
    autoload :BatchError, "github/mailchimp/batch_error"

    include Instrumentation::Model

    ServerErrorStatuses = 500...600

    # MailChimp considers these domains invalid.
    INVALID_DOMAIN_REGEXP = Regexp.new(
      /[@.](mailinator|googlegroups|yahoogroups)\.com\z/i,
    )

    # The master email list in MailChimp:
    # https://us11.admin.mailchimp.com/lists/members/?id=257769
    MASTER_LIST = "76ae42c08f"

    # The test list in MailChimp:
    # https://us11.admin.mailchimp.com/lists/members/?id=255157
    TEST_LIST = "46f7c08cd6"

    # The list for team admin onboarding campaign
    # https://us11.admin.mailchimp.com/lists/settings/defaults?id=364961
    GITHUB_TEAM_LIST = "0e5a3629d6"

    # Automation Campaigns
    # https://us11.admin.mailchimp.com/campaigns/wizard/autocampaigns?id=599449
    GENERIC_ONBOARDING_SERIES_WORKFLOW_ID            = "9715e29f35".freeze
    GENERIC_ONBOARDING_SERIES_WORKFLOW_EMAIL_ID      = "5c1636197b".freeze

    BEGINNER_ONBOARDING_SERIES_WORKFLOW_ID           = "0dee9495a5".freeze
    BEGINNER_ONBOARDING_SERIES_WORKFLOW_EMAIL_ID     = "58c03c75ae".freeze

    INTERMEDIATE_ONBOARDING_SERIES_WORKFLOW_ID       = "00f1f19bf3".freeze
    INTERMEDIATE_ONBOARDING_SERIES_WORKFLOW_EMAIL_ID = "abd7df44cf".freeze

    TEAM_ADMIN_ONBOARDING_WORKFLOW_ID = "f2caf0a229"
    TEAM_ADMIN_ONBOARDING_EMAIL_ID   = "755f1ef022"

    # Four hours in minutes; an extended timeout for batch operations
    LONG_TIMEOUT = 240

    attr_reader :email
    attr_reader :user

    # Public: Initialize a GitHub::Mailchimp instance.
    #
    # email - a UserEmail object
    #
    # Returns a GitHub::Mailchimp object.
    def initialize(email)
      unless email.is_a?(UserEmail)
        raise ArgumentError, "email must be a UserEmail"
      end

      @email = email
      @user  = email.user
    end

    # Public: Subscribe a group of emails to the list.
    #
    #   users - the User records to be subscribed.
    #
    # Returns Json that we can use to check the success of the job.
    def self.batch_subscribe(users)
      operations = users.map do |user|

        {
          method: "POST",
          path: "/lists/#{list_id}/members",
          operation_id: "subscribe-#{user.id}",
          body: {
            email_address: user.email,
            status: "subscribed",
            merge_fields: Mailchimp.merge_fields(user),
          }.to_json,
        }
      end

      Mailchimp.request(timeout: LONG_TIMEOUT).batches.create(body: { operations: operations })
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :batch_subscribe)
    end

    # Public: Unsubscribe a group of emails from the list.
    #
    #   emails - the UserEmail records to unsubscribe from MailChimp.
    #
    # Returns Json we can use to check the status of the batch operations.
    def self.batch_unsubscribe(emails:, list_id: Mailchimp.list_id)
      operations = emails.map do |email|
        {
            method: "PATCH",
            path: "/lists/#{list_id}/members/#{Mailchimp.member_id(email.email)}",
            operation_id: "unsubscribe-#{email.id}",
            body: { status: "unsubscribed" }.to_json,
        }
      end

      Mailchimp.request(timeout: LONG_TIMEOUT).batches.create(body: { operations: operations })
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :batch_unsubscribe)
    end

    # Public: Retrieve the status of a batch of MailChimp operations.
    #
    # See http://developer.mailchimp.com/documentation/mailchimp/reference/batches/ for more
    #
    # returns a Json response
    def self.find_batch(batch_id)
      Mailchimp.request.batches(batch_id).retrieve
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :find_batch)
    end

    # Internal: Merge fields sent to MailChimp when a user is subscribed
    #
    # It's important to send Strings instead of bare Booleans; the request fails
    # if the datatype doesn't match MailChimp's expectations.
    #
    # Returns a Hash.
    def self.merge_fields(user)
      {
        COUPON: user.coupons.first.try(:code),
        GDP_MEMBER: user.developer_program_member?.to_s,
        SIGNUPDATE: user.created_at.strftime("%m/%d/%Y"),
        USERNAME: user.login,
        USER_ID: user.id,
      }.delete_if { |_field, value| value.blank? }
    end

    # Internal: Merge fields sent to MailChimp when a user is subscribed to Team list
    #
    # It's important to send Strings instead of bare Booleans; the request fails
    # if the datatype doesn't match MailChimp's expectations.
    #
    # Returns a Hash.
    def self.team_merge_fields(user:, org:, active_admin:, active_user:, active_ghec_admin:, active_ghec_user:, active_free_admin:, active_free_user:, free_org_for_admin_campaign: nil, free_org_for_admin_campaign_at: nil, free_org_for_admin_campaign_active: nil)
      {
        USERNAME: user.login,
        USER_ID: user.id,
        ORG_NAME: org.name,
        ORG_ID: org.id,
        IS_ADMIN: active_admin.to_s,
        IS_USER: active_user.to_s,
        GHEC_USER: active_ghec_user.to_s,
        GHEC_ADMIN: active_ghec_admin.to_s,
        FREE_USER: active_free_user.to_s,
        FREE_ADMIN: active_free_admin.to_s,
        FOA_CAM: free_org_for_admin_campaign&.name,
        FOA_CAM_AT: free_org_for_admin_campaign_at,
        FOA_CAM_AC: free_org_for_admin_campaign_active.nil? ? nil : free_org_for_admin_campaign_active.to_s
      }.delete_if { |_field, value| value.blank? }
    end

    # Internal: Sets up a request object to make API calls.
    #
    # WARNING: Don't attempt to memoize this; multiple requests
    # from the same Gibbon::Request object will fail.
    #
    # Returns a Gibbon::Request object.
    def self.request(timeout: Gibbon::Request::DEFAULT_TIMEOUT)
      Gibbon::Request.new(timeout: timeout)
    end

    # Internal: Subscribers are identified by the MD5 hash
    # of the lowercase version of their email address.
    #
    # Returns an MD5 hash as a String.
    def self.member_id(email_address)
      Digest::MD5.hexdigest(email_address.downcase) # rubocop:disable GitHub/InsecureHashAlgorithm
    end

    # Public: deletes an email from MailChimp
    def delete(list_id: Mailchimp.list_id)
      GitHub.dogstats.distribution_time("mailchimp.duration", tags: ["action:delete"]) do
        list(list_id: list_id).members(member_id).delete
      end

      instrument :delete
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :delete)
    end

    # Public: Subscribe an email to the list.
    #
    # If an email already exists in MailChimp,
    # update it via upsert to be resubscribed.
    # Returns a Hash.
    def subscribe(list_id: Mailchimp.list_id, merge_fields: {})
      options = {
        body: {
          email_address: email_address,
          status: "subscribed",
          merge_fields: merge_fields.present? ? merge_fields : Mailchimp.merge_fields(user),
        },
      }

      GitHub.dogstats.distribution_time("mailchimp.duration", tags: ["action:subscribe"]) do
        list(list_id: list_id).members(member_id).upsert(**options)
      end

      instrument :subscribe, {
        signup_date: user.created_at.strftime("%m/%d/%Y"),
      }
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :subscribe)
    end

    # Public: Unsubscribe an email from the list.
    # Returns a Hash.
    def unsubscribe(list_id: Mailchimp.list_id)
      options = {
        body: {
          status: "unsubscribed",
        },
      }

      GitHub.dogstats.distribution_time("mailchimp.duration", tags: ["action:unsubscribe"]) do
        list(list_id: list_id).members(member_id).update(**options)
      end

      instrument :unsubscribe
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :unsubscribe)
    end

    # Public: Update a member in the list.
    #
    # Returns a Hash.
    def update_member(list_id: Mailchimp.list_id, merge_fields: {})
      options = {
        body: {
          email_address: email_address,
          status: "subscribed",
          merge_fields: merge_fields.present? ? merge_fields : Mailchimp.merge_fields(user),
        },
      }

      GitHub.dogstats.distribution_time("mailchimp.duration", tags: ["action:update_member"]) do
        list(list_id: list_id).members(member_id).update(**options)
      end

      instrument :update_member
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :update_member)
    end

    # Public: Retrieve the member record.
    #
    # Returns a Hash.
    def find_member(list_id: Mailchimp.list_id)
      GitHub.dogstats.distribution_time("mailchimp.duration", tags: ["action:find_member"]) do
        list(list_id: list_id).members(member_id).retrieve
      end
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :find_member) unless boom.status_code == 404
    end

    # Public: Start an automation workflow for the email.
    #
    # workflow_id       - MailChimp-given workflow id
    # workflow_email_id - MailChimp workflow email id
    #
    # Returns nil.
    def start_workflow(workflow_id:, workflow_email_id:)
      GitHub.dogstats.distribution_time("mailchimp.duration", tags: ["action:start_workflow"]) do
        Mailchimp.request.automations(workflow_id).emails(workflow_email_id).queue.create(
          body: { email_address: email_address },
        )
      end

      instrument :start_workflow, {
        mailchimp_workflow_id: workflow_id,
        mailchimp_workflow_email_id: workflow_email_id,
      }
    rescue Gibbon::MailChimpError => boom
      raise Error.new(boom, :start_workflow) unless boom.status_code == 404
    end

    # Public: Look up a subscriber by email. If the record exists,
    # execute the block. Otherwise, return nil.
    def ensure_subscriber_exists(list_id = Mailchimp.list_id, &block)
      find_member(list_id: list_id)
      yield
    rescue GitHub::Mailchimp::Error => boom
      if boom.status_code == 404
        nil
      else
        raise
      end
    end

    # Goal: make these private
    # Public: Returns the email address as a String.
    def email_address
      email.email
    end

    # Public: Whether or not MailChimp considers the email valid.
    # Returns a Boolean.
    def valid_email?
      !(email_address =~ INVALID_DOMAIN_REGEXP)
    end

    # Internal: Subscribers are identified by the MD5 hash
    # of the lowercase version of their email address.
    #
    # Returns an MD5 hash as a String.
    def member_id
      Mailchimp.member_id(email_address)
    end

    # Public: Returns a Gibbon::Request object with the MailChimp list.
    def list(list_id: Mailchimp.list_id)
      Mailchimp.request.lists(list_id)
    end

    # Private: The MailChimp email list id.
    # Returns a String.
    def self.list_id
      Rails.env.production? ? MASTER_LIST : TEST_LIST
    end

    # Public: Returns an array of MailChimp list ids.
    def self.list_ids
      [Mailchimp.list_id, GITHUB_TEAM_LIST]
    end

    # Private: The human-readable name of the Mailchimp list.
    # Returns a String.
    def self.list_name
      Rails.env.production? ? "GitHub Master List" : "User Growth Test"
    end

    private

    # Define the default payload for a MailChimp event.
    def event_payload
      {
        email: email_address,
        email_id: email.id,
        list_id: Mailchimp.list_id,
        list_name: Mailchimp.list_name,
        member_id: member_id,
        user: user,
        user_id: email.user_id,
      }.merge(event_context)
    end

    # We're overriding the event context because this method
    # expects an ActiveRecord object by default.
    def event_context
      {}
    end

    def event_prefix
      :mailchimp
    end
  end
end
