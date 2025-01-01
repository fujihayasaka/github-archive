# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateOrganizationRoutingToEligibleEmailJob < ApplicationJob
  queue_as :update_organization_routing_to_eligible_email

  class ServiceUnavailable < RuntimeError; end

  retry_on_dirty_exit

  retry_on(ServiceUnavailable, wait: 60.seconds, attempts: 3) do |_job, error|
    NotificationsFailbot.report(error)
  end

  # Public: Finds members in a business or organization that are no longer able to receive
  # email notifications due to notification restrictions, and updates their
  # routing settings to use an eligible email address if available.
  #
  # owner – the Business or Organization that has enabled notification restrictions.
  #
  # Returns nothing.
  def perform(owner)
    return unless owner.restrict_notifications_to_verified_domains?

    case owner
    when Organization
      perform_on_organization(owner)
    when Business
      owner.organizations.each do |organization|
        perform_on_organization(organization)
      end
    end

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

  # Private: does the work of of updating notification routing settings for members of a specific
  # organization. For Businesses, #perform above will call into this method for each organization
  # in the Business.
  #
  # organization - Organization whose routing settings we're updating
  #
  # Returns nothing.
  def perform_on_organization(organization)
    affected_members = organization.members - organization.members_without_eligible_email
    email_eligible_domains = organization.email_eligible_domain_urls

    affected_members.each_slice(100) do |member_slice|
      # Get the newsies settings for each member, since we only need to update this
      # for users who receive email notifications.
      newsies_response = GitHub.newsies.load_user_settings(member_slice.pluck(:id))
      raise ServiceUnavailable unless newsies_response.success?

      newsies_settings = newsies_response.value.index_by(&:user)

      ignore_email_role_ids = EmailRole.where(
        user_id: member_slice.pluck(:id),
        role: %w[hard_bounce stealth]
      ).pluck(:email_id)

      eligible_emails = UserEmail.without_ids(ignore_email_role_ids).
        where(user_id: member_slice.pluck(:id)).
        where(normalized_domain: email_eligible_domains).
        group_by(&:user_id)

      member_slice.each do |member|
        if setting = newsies_settings[member]
          next unless receives_email_notifications?(setting)
          next if organization.user_can_receive_email_notifications?(member)

          eligible_email = eligible_emails[member.id]&.first&.email

          next unless eligible_email.present?

          with_write do
            NotificationUserSetting.throttle do
              response = GitHub.newsies.get_and_update_settings(member) do |settings|
                settings.email organization, eligible_email
              end

              raise ServiceUnavailable unless response.success?
            end
          end
        end
      end
    end
  end
end
