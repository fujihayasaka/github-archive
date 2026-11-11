# typed: true
# frozen_string_literal: true

# This job verifies if a user has unsubscribed from marketing emails by checking CPM and retrieves an unsubscribe URL from CPM. If the user is unsubscribed, they are added to a removal list via SendgridRemoveJob. If the user is contactable, they are added to an import list via SendgridImportJob.

module Nurture
  class CpmSyncJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions attempts: 5
    retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 5

    # scheduling is done in timers.fe.rb
    schedule interval: ENV.fetch("CPM_SYNC_FREQUENCY_SECONDS", "300").to_i # default to 5 minutes

    queue_as :nurture_campaign_sync

    # Controls execution time by limiting job size
    MAX_BATCH_SIZE = ENV.fetch("CPM_SYNC_BATCH_SIZE", "50").to_i
    # The remove job has a limit of 100 contacts, so only decrease this value if making adjustments
    MAX_CONTACTS_TO_REMOVE = 100
    # How often a user should be checked in the CPM
    USER_UPDATE_FREQUENCY_SECONDS = ENV.fetch("CPM_SYNC_USER_UPDATE_FREQUENCY_SECONDS", "86400").to_i # default to 24 hours
    LOCK_TTL_SECONDS = ENV.fetch("CPM_SYNC_LOCK_TTL_SECONDS", "300").to_i # default to 5 minutes

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
      lock_ttl = LOCK_TTL_SECONDS

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
          GitHub.logger.info(
            "info.message" => "CPM sync max batch size: #{MAX_BATCH_SIZE}.",
          )

          user_marketing_consents = self.class.get_batch_of_user_marketing_consents

          if user_marketing_consents.empty?
            GitHub.logger.info(
              "info.message" => "No user marketing consents found that meet sync criteria.  Skipping job.",
            )

            GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.skipped", tags: ["skipped:no_user_signups"])

            return
          end

          GitHub.dogstats.count("nurture_campaign.cpm_sync_job.processed_count", user_marketing_consents.size)

          # 30 is the maximum number of people CPM can process at once
          user_marketing_consents.in_groups_of(30, false) do |group|
            GitHub.dogstats.increment("nurture_campaign.cpm_sync_job.cpm_sync_group.start")

            emails = group.map(&:email)

            contacts = self.class.retrieve_contactability_status(emails)

            user_marketing_consent_by_email = group.index_by(&:email)
            to_touch = []

            contacts.each do |contact|
              user_marketing_consent = user_marketing_consent_by_email[contact[:email]]

              self.class.process_contact(contact, user_marketing_consent)
              to_touch << user_marketing_consent.id if user_marketing_consent

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

            # update each user signup updated_at and last_verified_with_cpm_at date to indicate that we have processed it
            with_write do
              self.class.update_user_marketing_consents(to_touch) unless to_touch.empty?
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
    def self.get_batch_of_user_marketing_consents
      if FeatureFlag.vexi.enabled?(:nurture_campaign_staff_testing, default: false)
        vexi_user_ids = FeatureFlag.vexi.actors_value_or_raise(:receive_marketing_emails) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        user_ids = vexi_user_ids.map do |user|
          user.split(":").last
        end

        UserMarketingConsent.where(user_id: user_ids)
      else
        UserMarketingConsent
          .where(marketing_consent: :explicit_optin)
          .where(onboarding_optout_date: nil)
          .where(is_eligible_for_nurture_campaign: true)
          .where("last_verified_with_cpm_at IS NULL OR last_verified_with_cpm_at < ?", USER_UPDATE_FREQUENCY_SECONDS.seconds.ago)
          .order(:last_verified_with_cpm_at)
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

    sig { params(contact: T::Hash[Symbol, T.untyped], user_marketing_consent: UserMarketingConsent).void }
    def self.process_contact(contact, user_marketing_consent)
      user = user_marketing_consent.user

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

    sig { params(ids: T::Array[Integer]).void }
    def self.update_user_marketing_consents(ids)
      UserMarketingConsent.where(id: ids).touch_all(:last_verified_with_cpm_at, :updated_at)
    end
  end
end
