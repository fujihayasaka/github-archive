# typed: true
# frozen_string_literal: true

module Nurture
  class CpmSyncJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions attempts: 5
    retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 5

    # scheduling is done in timers.fe.rb
    schedule interval: 5.minutes

    queue_as :nurture_campaign_sync

    # Controls execution time by limiting job size
    MAX_BATCH_SIZE = 3000
    # The remove job has a limit of 100 contacts, so only decrease this value if making adjustments
    MAX_CONTACTS_TO_REMOVE = 100
    # How often a user should be checked in the CPM
    USER_SYNC_FREQUENCY = 1.day

    def self.contacts_to_import
      @contacts_to_import ||= []
    end

    def self.contacts_to_remove
      @contacts_to_remove ||= []
    end

    sig { void }
    def perform
      # only allow one instance of the job to run at a time
      lock_key = "nurture_campaign_cpm_sync"
      concurrent_jobs = 1
      lock_ttl = 10.minutes

      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
        self.class.contacts_to_import.clear
        self.class.contacts_to_remove.clear

        return unless self.class.job_ff_enabled?
        return unless self.class.env_vars_present?

        GitHub.dogstats.time("nurture_campaign.cpm_sync_job") do
          GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.start")

          GitHub.logger.info(
            "info.message" => "Starting cpm sync job",
          )

          user_signups = self.class.get_batch_of_user_signups

          if user_signups.empty?
            GitHub.logger.info(
              "info.message" => "No user signups found that meet sync criteria.  Skipping job.",
            )

            GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.skipped", tags: ["skipped:no_user_signups"])

            return
          end

          GitHub.dogstats.count("nurture_campaign.cpm_sync_job.processed_count", user_signups.size)

          user_signups.in_groups_of(30, false) do |group|
            GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.cpm_sync_group.start")

            emails = group.map(&:email)

            contacts = self.class.retrieve_contactability_status(emails)

            contacts.each do |contact|
              user_signup = group.find { |user_signup| user_signup.email == contact[:email] }

              self.class.process_contact(contact, user_signup)

              with_write do
                # touch each user signup to update the last updated date to indicate that we have processed it
                user_signup.touch
              end

              if self.class.contacts_to_remove.size >= MAX_CONTACTS_TO_REMOVE
                GitHub.logger.info(
                  "info.message" => "Trigger Sendgrid remove job",
                  "gh.nurture.cpm_sync_job.contacts_to_remove.count" => self.class.contacts_to_remove.size,
                )

                GitHub.dogstats.count("nurture_campaign.cpm_sync_job.trigger_sendgrid_remove.count", self.class.contacts_to_remove.size)
                GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.trigger_sendgrid_remove")

                if FeatureFlag.vexi.enabled?(:nurture_campaign_staff_testing, default: false)
                  GitHub.logger.info(
                    "info.message" => "Staff testing is enabled.  Logging payload.",
                    "gh.nurture.cpm_sync_job.contacts_to_remove.payload" => self.class.contacts_to_remove.to_s,
                  )
                end

                SendgridRemoveJob.perform_later(self.class.contacts_to_remove)

                # clear out the list for the next batch
                self.class.contacts_to_remove.clear
              end
            end

            GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.cpm_sync_group.finish")
          end

          if !self.class.contacts_to_import.empty?
            GitHub.logger.info(
              "info.message" => "Trigger Sendgrid import job",
              "gh.nurture.cpm_sync_job.contacts_to_import.count" => self.class.contacts_to_import.size,
            )

            GitHub.dogstats.count("nurture_campaign.cpm_sync_job.trigger_sendgrid_import.count", self.class.contacts_to_import.size)
            GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.trigger_sendgrid_import")

            if FeatureFlag.vexi.enabled?(:nurture_campaign_staff_testing, default: false)
              GitHub.logger.info(
                "info.message" => "Staff testing is enabled.  Logging payload.",
                "gh.nurture.cpm_sync_job.contacts_to_import.payload" => self.class.contacts_to_import.to_s,
              )
            end

            SendgridImportJob.perform_later(self.class.contacts_to_import)
          else
            GitHub.logger.info(
              "info.message" => "No contacts to import.  Skipping import.",
            )
          end

          if !self.class.contacts_to_remove.empty?
            GitHub.logger.info(
              "info.message" => "Trigger Sendgrid remove job",
              "gh.nurture.cpm_sync_job.contacts_to_remove.count" => self.class.contacts_to_remove.size,
            )

            GitHub.dogstats.count("nurture_campaign.cpm_sync_job.trigger_sendgrid_remove.count", self.class.contacts_to_remove.size)
            GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.trigger_sendgrid_remove")

            if FeatureFlag.vexi.enabled?(:nurture_campaign_staff_testing, default: false)
              GitHub.logger.info(
                "info.message" => "Staff testing is enabled.  Logging payload.",
                "gh.nurture.cpm_sync_job.contacts_to_remove.payload" => self.class.contacts_to_remove.to_s,
              )
            end

            SendgridRemoveJob.perform_later(self.class.contacts_to_remove)
          else
            GitHub.logger.info(
              "info.message" => "No contacts to remove.  Skipping remove.",
            )
          end

          GitHub.logger.info(
            "info.message" => "Finished cpm sync job",
          )

          GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.finish")
        end
      end
    end

    sig { returns(T::Boolean) }
    def self.job_ff_enabled?
      return true if FeatureFlag.vexi.enabled?(:run_nurture_campaign_jobs, default: false)

      GitHub.logger.info(
        "info.message" => "run_nurture_campaign_jobs FF is disabled.  Skipping job.",
      )

      GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.skipped", tags: ["skipped:ff_disabled"])

      false
    end

    sig { returns(T::Boolean) }
    def self.env_vars_present?
      return true if ENV["SIGNUP_SENDGRID_TOPIC_ID"]

      GitHub.logger.error(
        "error.message" => "Topic ID not set",
      )

      GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.error", tags: ["error:missing_env"])

      false
    end

    sig { returns(ActiveRecord::Relation) }
    def self.get_batch_of_user_signups
      if FeatureFlag.vexi.enabled?(:nurture_campaign_staff_testing, default: false)
        vexi_user_ids = FeatureFlag.vexi.actors_value_or_raise(:receive_marketing_emails) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        user_ids = vexi_user_ids.map do |user|
          user.split(":").last
        end

        UserSignup.where(user_id: user_ids)
      else
        # in a worst case scenario, it can take up to 4 hours for data to be available in CPM, so we don't want to sync users who have just signed up
        # https://microsoft.sharepoint.com/teams/CPMHelp/SitePages/Onboarding-to-CPM.aspx#please-allow-4-hours-to-ensure-consent-updates-are-propagated-across-all-regions
        UserSignup.where(marketing_consent: :explicit_optin, onboarding_optout_date: nil)
          .and(
            UserSignup.where("updated_at < ?", USER_SYNC_FREQUENCY.ago)
              .or(UserSignup.where("updated_at = created_at AND created_at < ?", 4.hours.ago))
          )
          .where.not("updated_at = created_at AND created_at < ?", 1.day.ago)
          .where("created_at >= ?", 21.days.ago)
          .limit(MAX_BATCH_SIZE)
      end
    end

    sig { params(emails: T::Array[String]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.retrieve_contactability_status(emails)
      GitHub.logger.info(
        "info.message" => "Retrieving contactability status",
        "nurture_campaign.cpm_sync_job.emails.count" => emails.size,
      )

      GitHub.dogstats.count("nurture_campaign.cpm_sync_job.contactability_requested.count", emails.size)
      GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.check_contactability")

      cpm_client = Cpm::RestApiClient.new
      contactability_status = cpm_client.check_email_contactability(emails, T.must(ENV["SIGNUP_SENDGRID_TOPIC_ID"]), "nurture_campaign_sync")

      if contactability_status[:timeout]
        GitHub.logger.error(
          "error.message" => "Error checking contactability",
          "error.cpm_error" => "timeout",
          "nurture_campaign.cpm_sync_job.emails" => emails,
        )

        GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.error", tags: ["error:cpm_timeout"])

        return []
      end

      if contactability_status[:has_error]
        GitHub.logger.error(
          "error.message" => "Error checking contactability",
          "error.cpm_error" => contactability_status[:message],
          "nurture_campaign.cpm_sync_job.emails" => emails,
        )

        GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.error", tags: ["error:check_contactability"])

        return []
      end

      if contactability_status[:contacts].empty?
        GitHub.logger.error(
          "error.message" => "No contacts found",
        )

        GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.error", tags: ["error:no_contacts"])

        return []
      end

      GitHub.logger.info(
        "info.message" => "Contactability status retrieved",
        "nurture_campaign.cpm_sync_job.contactability_status.count" => contactability_status[:contacts].size,
      )

      GitHub.dogstats.count("nurture_campaign.cpm_sync_job.contactability_retrieved.count", contactability_status[:contacts].size)

      if FeatureFlag.vexi.enabled?(:nurture_campaign_staff_testing, default: false)
        GitHub.logger.info(
          "info.message" => "Staff testing is enabled.  Logging payload.",
          "gh.nurture.cpm_sync_job.contactability_status.payload" => contactability_status[:contacts].to_s,
        )
      end

      contactability_status[:contacts]
    end

    sig { params(contact: T::Hash[Symbol, T.untyped], user_signup: UserSignup).void }
    def self.process_contact(contact, user_signup)
      check_last_updated_date(user_signup)

      user = user_signup.user

      unless user_exists?(user, contact[:email])
        add_contact_to_remove_list(contact[:email])
        return
      end

      # CAVEAT: If we disabled the ff, we will stop syncing users
      unless user_is_opted_in_to_marketings_email_ff?(T.must(user), contact[:email])
        return
      end

      unless contact_is_present_in_cpm?(contact[:isPresent], contact[:email])
        add_contact_to_remove_list(contact[:email])
        return
      end

      unless is_contactable?(contact[:canContact], contact[:email])
        add_contact_to_remove_list(contact[:email])
        return
      end

      GitHub.logger.info(
        "info.message" => "Contact is present in CPM and can be contacted",
        "nurture_campaign.cpm_sync_job.email" => contact[:email],
      )

      GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.contactable")

      add_contact_to_import_list(
        contact[:email],
        T.must(user).display_login,
        T.must(user).id,
        contact[:unsubscribeUrl]
      )
    end

    def self.check_last_updated_date(user_signup)
      if user_signup.updated_at < 4.days.ago
        GitHub.logger.info(
          "info.message" => "User signup was last updated more than 4 days ago",
          "nurture_campaign.cpm_sync_job.email" => user_signup.email,
        )

        GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.updated_over_4_days_ago")
      end
    end

    sig { params(user: T.nilable(User), email: String).returns(T::Boolean) }
    def self.user_exists?(user, email)
      return true if user.present?

      GitHub.logger.error(
        "error.message" => "User not found",
        "nurture_campaign.cpm_sync_job.email" => email,
      )

      GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.error", tags: ["error:user_not_found"])

      false
    end

    sig { params(user: User, email: String).returns(T::Boolean) }
    def self.user_is_opted_in_to_marketings_email_ff?(user, email)
      return true if user.feature_flag_enabled?(:receive_marketing_emails, default: false)

      GitHub.logger.info(
        "info.message" => "User is not opted into ff",
        "nurture_campaign.cpm_sync_job.email" => email,
      )

      GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.user_ff_disabled")

      false
    end

    sig { params(is_present: T::Boolean, email: String).returns(T::Boolean) }
    def self.contact_is_present_in_cpm?(is_present, email)
      return true if is_present

      GitHub.logger.info(
        "info.message" => "Contact not present in CPM",
        "nurture_campaign.cpm_sync_job.email" => email,
      )

      GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.not_present")

      false
    end

    sig { params(can_contact: T::Boolean, email: String).returns(T::Boolean) }
    def self.is_contactable?(can_contact, email)
      return true if can_contact

      GitHub.logger.info(
        "info.message" => "Contact is present in CPM but cannot be contacted",
        "nurture_campaign.cpm_sync_job.email" => email,
      )

      GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.unsubscribed")

      false
    end

    sig { params(email: String, display_login: String, user_id: Integer, unsubscribe_url: String).void }
    def self.add_contact_to_import_list(email, display_login, user_id, unsubscribe_url)
      contacts_to_import << SendgridData.new(
        email,
        display_login,
        user_id,
        unsubscribe_url,
      ).to_serialized_hash
    end

    sig { params(email: String).void }
    def self.add_contact_to_remove_list(email)
      contacts_to_remove << SendgridData.new(email, nil, nil, nil).to_serialized_hash
    end
  end
end
