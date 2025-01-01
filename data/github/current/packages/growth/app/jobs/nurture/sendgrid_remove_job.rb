# typed: true
# frozen_string_literal: true

require "csv"
require "faraday"
require "github/sendgrid/error"

module Nurture
  class SendgridRemoveJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions attempts: 5
    retry_on GitHub::Sendgrid::Error, wait: :polynomially_longer, attempts: 5

    queue_as :nurture_campaign_sync

    MAX_EMAIL_COUNT = 100
    BASE_URL = "https://api.sendgrid.com"

    def perform(data)
      return unless self.class.job_ff_enabled?
      return unless self.class.env_vars_present?

      if data.empty?
        GitHub.logger.error(
          "error.message": "No contact emails sent to remove from Sendgrid",
        )
        GitHub.dogstats.increment("nurture_campaign.sendgrid_remove_contacts_job.error", tags: ["error:no_emails"])
        return
      end

      emails = data.map do |sgd|
        SendgridData.from_serialized_hash(sgd).email
      end

      emails = emails.uniq

      if emails.count > MAX_EMAIL_COUNT
        GitHub.logger.error(
          "error.message": "Email count exceeded #{MAX_EMAIL_COUNT} max: #{emails.count}",
        )

        GitHub.dogstats.increment(
          "nurture_campaign.sendgrid_remove_contacts_job.error",
          tags: ["error:email_count_exceeded"]
        )

        return
      end

      GitHub.dogstats.time("nurture_campaign.sendgrid_remove_contacts_job") do
        GitHub.dogstats.increment("nurture_campaign.sendgrid_remove_contacts_job.start")
        GitHub.dogstats.count(
          "nurture_campaign.sendgrid_remove_contacts_job.contact_ids.count",
          emails.count
        )

        GitHub.logger.info(
          "info.message": "Starting sendgrid remove job",
          "gh.nurture.sendgrid_remove_contacts_job.emails.count": emails.count,
        )

        begin
          # Get contact ids from emails
          # https://www.twilio.com/docs/sendgrid/api-reference/contacts/get-contacts-by-emails
          contact_ids = self.class.get_contact_ids_from_sendgrid(emails)
          is_empty_contact_ids = handle_empty_contact_ids(emails, contact_ids)
          return if is_empty_contact_ids

          # Remove contacts from a list
          # https://www.twilio.com/docs/sendgrid/api-reference/lists/remove-contacts-from-a-list
          job_id = self.class.remove_contacts_from_sendgrid(contact_ids)
          GitHub.logger.info(
            "info.message": "Created sendgrid remove job",
            "gh.nurture.sendgrid_remove_contacts_job.job_id": job_id,
          )

          # Add emails to suppression list
          # https://www.twilio.com/docs/sendgrid/api-reference/suppressions-suppressions/add-suppressions-to-a-suppression-group
          recipient_emails = self.class.add_emails_to_sendgrid_suppression_group(emails)
          error = self.class.handle_suppression_group_response(emails, recipient_emails)
          return if error

          # update onboard_optout_date on user_signup model
          UserSignup.throttle_writes do
            self.class.update_user_signups_optout_date(recipient_emails)
          end

          GitHub.dogstats.count("nurture_campaign.sendgrid_remove_contacts_job.removed_successfully.count", emails.count)
          GitHub.dogstats.increment("nurture_campaign.sendgrid_remove_contacts_job.finish")
        rescue JSON::ParserError => err
          GitHub.logger.error(
            "error.message": "Error parsing JSON response from Sendgrid",
            "error.body": err.message,
            "gh.nurture.sendgrid_remove_contacts_job.job_id": job_id,
          )

          GitHub.dogstats.increment("nurture_campaign.sendgrid_remove_contacts_job.error", tags: ["error:json_parse"])
        rescue Faraday::Error => err
          GitHub.logger.error(
            "error.message": "Error removing contacts from Sendgrid",
            "error.status": err.response[:status],
            "error.body": err.response[:body],
            "gh.nurture.sendgrid_remove_contacts_job.job_id": job_id,
          )

          raise GitHub::Sendgrid::Error.new(err, :remove)
        end
      end
    end

    sig { returns(T::Boolean) }
    def self.job_ff_enabled?
      return true if GitHub.flipper[:run_nurture_campaign_jobs].enabled?

      GitHub.logger.info(
        "info.message": "run_nurture_campaign_jobs FF is disabled.  Skipping job.",
      )

      GitHub.dogstats.increment("nurture_campaign.remove_job.skipped", tags: ["skipped:ff_disabled"])

      false
    end

    sig { returns(T::Boolean) }
    def self.env_vars_present?
      return true if ENV["SIGNUP_SENDGRID_API_KEY"].present? &&
                     ENV["SIGNUP_SENDGRID_NURTURE_LIST_ID"].present? &&
                     ENV["SIGNUP_SENDGRID_NURTURE_SUPPRESSION_GROUP_ID"].present?

      GitHub.logger.error(
        "error.message": "SIGNUP_SENDGRID_API_KEY, SIGNUP_SENDGRID_NURTURE_LIST_ID, or " \
          "SIGNUP_SENDGRID_NURTURE_SUPPRESSION_GROUP_ID environment variable is not set",
      )

      GitHub.dogstats.increment("nurture_campaign.remove_job.error", tags: ["error:missing_env"])

      false
    end

    sig { returns(String) }
    def self.remove_url
      "/v3/marketing/lists/#{ENV["SIGNUP_SENDGRID_NURTURE_LIST_ID"]}/contacts"
    end

    sig { returns(String) }
    def self.suppression_url
      "/v3/asm/groups/#{ENV["SIGNUP_SENDGRID_NURTURE_SUPPRESSION_GROUP_ID"]}/suppressions"
    end

    sig { returns(String) }
    def self.search_url
      "/v3/marketing/contacts/search/emails"
    end

    sig { params(emails: T::Array[String]).returns(T::Array[String]) }
    def self.get_contact_ids_from_sendgrid(emails)
      # Sendgrid API v3
      sg = GitHub::FaradayClient.external("Sendgrid", BASE_URL)

      resp = sg.post do |req|
        req.url search_url
        req.headers["Authorization"] = "Bearer #{ENV["SIGNUP_SENDGRID_API_KEY"]}"
        req.headers["Content-Type"] = "application/json"
        req.body = GitHub::JSON.encode({ emails: })
      end

      GitHub.dogstats.increment(
        "nurture_campaign.sendgrid_remove_contacts_job.contact_ids.request",
        tags: ["status:#{resp.status}"]
      )

      return [] if no_contact_ids_for_emails_found?(resp)

      if resp.status != 200
        GitHub.logger.error(
          "error.message": "Error getting contact IDs from Sendgrid",
          "error.status": resp.status,
          "error.body": resp.body,
          "gh.nurture.sendgrid_remove_contacts_job.emails": emails
        )

        raise GitHub::Sendgrid::Error.new(resp, :get_contact_ids_from_sendgrid)
      end

      body = JSON.parse(resp.body)

      result = body.fetch("result", [])
      if result.empty?
        GitHub.logger.error(
          "error.message": "No contact IDs found for emails",
          "error.status": resp.status,
          "error.body": resp.body,
          "gh.nurture.sendgrid_remove_contacts_job.emails": emails,
        )
        GitHub.dogstats.increment(
          "nurture_campaign.sendgrid_remove_contacts_job.error",
          tags: ["error:no_contact_ids"]
        )
        raise GitHub::Sendgrid::Error.new(resp, :get_contact_ids_from_sendgrid)
      end

      result.map { |_, contact| contact.dig("contact", "id") }.compact
    end

    sig { params(resp: Faraday::Response).returns(T::Boolean) }
    def self.no_contact_ids_for_emails_found?(resp)
      # https://www.twilio.com/docs/sendgrid/api-reference/contacts/search-contacts#:Raslaatasm:-404
      resp.status == 404
    end

    sig { params(emails: T::Array[String], contact_ids: T::Array[String]).returns(T::Boolean) }
    def handle_empty_contact_ids(emails, contact_ids)
      empty_contact_ids = false
      if contact_ids.empty?
        GitHub.logger.info(
          "info.message": "No contact IDs to remove from Sendgrid",
          "gh.nurture.sendgrid_remove_contacts_job.emails": emails,
        )
        GitHub.dogstats.increment(
          "nurture_campaign.sendgrid_remove_contacts_job.no_contact_ids",
        )
        GitHub.dogstats.count(
          "nurture_campaign.sendgrid_remove_contacts_job.user_not_in_sendgrid.count",
          emails.count
        )
        empty_contact_ids = true
      end
      empty_contact_ids
    end

    sig { params(contact_ids: T::Array[String]).returns(String) }
    def self.remove_contacts_from_sendgrid(contact_ids)
      # Sendgrid API v3
      sg = GitHub::FaradayClient.external("Sendgrid", BASE_URL)

      resp = sg.delete do |req|
        req.url remove_url
        req.headers["Authorization"] = "Bearer #{ENV["SIGNUP_SENDGRID_API_KEY"]}"
        req.headers["Content-Type"] = "application/json"
        req.params = { "contact_ids": contact_ids.join(",") }
      end

      GitHub.dogstats.increment(
        "nurture_campaign.sendgrid_remove_contacts_job.remove_contacts.request",
        tags: ["status:#{resp.status}"]
      )

      if resp.status != 202
        # Sendgrid API v3 returns 202 Accepted for successful delete
        GitHub.logger.error(
          "error.message": "Error removing contacts from Sendgrid",
          "error.status": resp.status,
          "error.body": resp.body,
        )

        raise GitHub::Sendgrid::Error.new(resp, :remove_contacts_from_sendgrid)
      end

      job_id = JSON.parse(resp.body).fetch("job_id", nil)

      if job_id.nil?
        GitHub.logger.error(
          "error.message": "Error getting job ID from Sendgrid",
          "error.status": resp.status,
          "error.body": resp.body,
          "gh.nurture.sendgrid_remove_contacts_job.job_id": job_id,
        )
        raise GitHub::Sendgrid::Error.new(resp, :remove_contacts_from_sendgrid)
      end

      job_id
    end

    sig { params(emails: T::Array[String]).returns(T::Array[String]) }
    def self.add_emails_to_sendgrid_suppression_group(emails)
      # Sendgrid API v3
      sg = GitHub::FaradayClient.external("Sendgrid", BASE_URL)

      resp = sg.post do |req|
        req.url suppression_url
        req.headers["Authorization"] = "Bearer #{ENV["SIGNUP_SENDGRID_API_KEY"]}"
        req.headers["Content-Type"] = "application/json"
        req.body = GitHub::JSON.encode({ "recipient_emails": emails })
      end

      GitHub.dogstats.increment(
        "nurture_campaign.sendgrid_remove_contacts_job.supression_group.request",
        tags: ["status:#{resp.status}"]
      )

      if resp.status != 201
        # Sendgrid API v3 returns 200 OK for successful search
        GitHub.logger.error(
          "error.message": "Error adding emails to Sengrid suppression group",
          "error.status": resp.status,
          "error.body": resp.body,
        )

        raise GitHub::Sendgrid::Error.new(resp, :add_emails_to_sendgrid_suppression_group)
      end

      body = JSON.parse(resp.body)

      recipient_emails = body.fetch("recipient_emails", [])
      if recipient_emails.empty?
        GitHub.logger.error(
          "error.message": "No recipient emails found in Sendgrid suppression group",
          "error.status": resp.status,
          "error.body": resp.body,
          "gh.nurture.sendgrid_remove_contacts_job.emails": emails,
        )
        GitHub.dogstats.increment(
          "nurture_campaign.sendgrid_remove_contacts_job.error",
          tags: ["error:no_recipient_emails"]
        )
        raise GitHub::Sendgrid::Error.new(resp, :add_emails_to_sendgrid_suppression_group)
      end

      recipient_emails
    end

    sig { params(emails: T::Array[String], recipient_emails: T::Array[String]).returns(T::Boolean) }
    def self.handle_suppression_group_response(emails, recipient_emails)
      emails = emails.map(&:downcase)
      recipient_emails = recipient_emails.map(&:downcase)

      has_error = false
      email_info = {
        "gh.nurture.sendgrid_remove_contacts_job.recipient_emails.count": recipient_emails.count,
        "gh.nurture.sendgrid_remove_contacts_job.emails.count": emails.count,
        "gh.nurture.sendgrid_remove_contacts_job.emails": emails,
        "gh.nurture.sendgrid_remove_contacts_job.recipient_emails": recipient_emails,
      }
      if Set.new(emails) == Set.new(recipient_emails)
        info = {
          "info.message": "Added emails to sendgrid suppression group.",
        }
        info = info.merge!(email_info)
        GitHub.logger.info(info)
      else
        unsuppressed_emails = emails - recipient_emails
        error = {
          "error.message": "The recipient emails do not match the emails list sent to suppression group.",
          "gh.nurture.sendgrid_remove_contacts_job.unsuppressed_emails": unsuppressed_emails,
        }
        error = error.merge!(email_info)
        GitHub.logger.error(error)
        GitHub.dogstats.increment(
          "nurture_campaign.sendgrid_remove_contacts_job.error",
          tags: ["error:emails_mismatch"]
        )
        GitHub.dogstats.count(
          "nurture_campaign.sendgrid_remove_contacts_job.unsuppressed_emails.count",
          unsuppressed_emails.count
        )
        has_error = true
      end
      has_error
    end

    sig { params(emails: T::Array[String]).void }
    def self.update_user_signups_optout_date(emails)
      begin
        updated_count = UserSignup.where(
          email: emails
        ).update_all(
          onboarding_optout_date: Time.current.utc
        )

        GitHub.logger.info(
          "info.message": "Updated user signups with current date for onboarding optout date",
          "gh.nurture.sendgrid_remove_contacts_job.user_signups_updated": updated_count,
        )
        GitHub.dogstats.count(
          "nurture_campaign.sendgrid_remove_contacts_job.user_signups.updated", updated_count
        )
      rescue ActiveRecord::AdapterTimeout, ActiveRecord::ConnectionTimeoutError => e
        GitHub.logger.error(
          "error.message": "Query timeout updating user signups optout date",
          "error.class": e.class.name,
          "error.details": e.message,
          "gh.nurture.sendgrid_remove_contacts_job.emails_count": emails.size
        )

        GitHub.dogstats.increment(
          "nurture_campaign.sendgrid_remove_contacts_job.error",
          tags: ["error:query_timeout"]
        )

        # Re-raise to let job retry handle
        raise
      rescue StandardError => e
        GitHub.logger.error(
          "error.message": "Error updating user signups optout date",
          "error.class": e.class.name,
          "error.details": e.message,
          "gh.nurture.sendgrid_remove_contacts_job.emails_count": emails.size
        )

        GitHub.dogstats.increment(
          "nurture_campaign.sendgrid_remove_contacts_job.error",
          tags: ["error:unexpected_error"]
        )

        # Re-raise to let job retry handle
        raise
      end
    end
  end
end
