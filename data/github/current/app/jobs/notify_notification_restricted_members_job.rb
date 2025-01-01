# typed: true
# frozen_string_literal: true

class NotifyNotificationRestrictedMembersJob < ApplicationJob
  queue_as :mailers

  class ServiceUnavailable < RuntimeError; end

  retry_on(ServiceUnavailable, wait: 10.seconds, attempts: 5) do |_job, error|
    Failbot.report(error)
  end

  # Public: Finds members in an organization that are no longer able to receive
  #         email notifications due to notification restrictions, and sends them
  #         an email informing them of that. Also triggers a hydro event to record
  #         that notifications were restricted and how many users were affected.
  #
  # domain_owner   – the Organization or Business that has enabled notification restrictions
  # actor          - current_user who had made the change
  # notify_members - do we need to notify members? If not, just trigger the hydro event
  #                  (optional, true by default)
  #
  # Returns nothing.
  def perform(domain_owner, actor:, notify_members: true)
    affected_users_count = 0
    if notify_members
      members = domain_owner.members_without_eligible_email

      # Get the newsies settings for each member, since we only want to send
      # this email to users who receive email notifications.
      newsies_response = GitHub.newsies.load_user_settings(members.pluck(:id))
      raise ServiceUnavailable unless newsies_response.success?

      newsies_settings = newsies_response.value.index_by(&:user)

      members.each do |member|
        if setting = newsies_settings[member]
          next unless receives_email_notifications?(setting)

          affected_users_count += 1
          case domain_owner
          when Organization
            OrganizationMailer.notification_restrictions_enabled(member, domain_owner).deliver_later
          when Business
            organizations = domain_owner.orgs_for_member_without_eligible_email(member)
            BusinessMailer.notification_restrictions_enabled(member, domain_owner, organizations).deliver_later
          end
        end
      end
    end

    GlobalInstrumenter.instrument("verifiable_domains.notification_restrictions_enabled", {
      owner: domain_owner,
      domains: VerifiableDomain.usable_for(domain_owner).verified,
      actor: actor,
      affected_users_count: affected_users_count
    })
  end

  private

  # Private: Does this newsies config specify that the user should receive
  #          email notifications?
  #
  # settings - A Newsies::Settings object.
  #
  # Returns a Boolean.
  def receives_email_notifications?(setting)
    setting.participating_email? || setting.subscribed_email?
  end
end
