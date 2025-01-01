# typed: true
# frozen_string_literal: true

module Organization::NotificationRestrictionsDependency
  extend ActiveSupport::Concern

  # Public: The members of this organization who do not have an email
  # address eligible to receive notifications when notifications restrictions are
  # enabled. Conditions for eligibility:
  #   - email address must be verified (Note: When GitHub.email_verification_enabled? returns
  #     false, user emails cannot be verified in the current environment. So the check for whether
  #     a user email is verified is bypassed.)
  #   - email address must from a verified or approved domain (domain can belong
  #     to the org, or to the parent enterprise)
  #
  # domains - VerifiableDomain's for this Organization. Will call email_eligible_domains to
  #           get the domains if parameter is not specified. Note: email_eligible_domains will
  #           load the domains, so if the caller is async, it needs to load the domains first via
  #           async_email_eligible_domains, then pass them in to here. Or if the caller has
  #           already pre-loaded the domains, it can pass them into here to skip the extra db query.
  #
  # Returns: ActiveRecord::Relation<User>
  def members_without_eligible_email(domains = T.unsafe(self).email_eligible_domains)
    return User.none unless domains.any?

    User.where(id: member_ids_without_eligible_email(domains))
  end

  # Public: The members of this organization who do not have an email
  # address eligible to receive notifications when notifications restrictions are
  # enabled. Conditions for eligibility:
  #   - email address must be verified (Note: When GitHub.email_verification_enabled? returns
  #     false, user emails cannot be verified in the current environment. So the check for whether
  #     a user email is verified is bypassed.)
  #   - email address must from a verified or approved domain (domain can belong
  #     to the org, or to the parent enterprise)
  #
  # domains - VerifiableDomain's for this Organization. Will call email_eligible_domains to
  #           get the domains if parameter is not specified. Note: email_eligible_domains will
  #           load the domains, so if the caller is async, it needs to load the domains first via
  #           async_email_eligible_domains, then pass them in to here. Or if the caller has
  #           already pre-loaded the domains, it can pass them into here to skip the extra db query.
  #
  # Returns: GitHub::BatchedScope::BatchedScopeQuery
  def batched_members_without_eligible_email(domains = T.unsafe(self).email_eligible_domains)
    return User.none unless domains.any?

    User.batched_scope(:id, values: member_ids_without_eligible_email(domains))
  end

  # Public: The number of members of this organization who do not have an email
  # address eligible to receive notifications when notifications restrictions are
  # enabled. Conditions for eligibility:
  #   - email address must be verified (Note: When GitHub.email_verification_enabled? returns
  #     false, user emails cannot be verified in the current environment. So the check for whether
  #     a user email is verified is bypassed.)
  #   - email address must from a verified or approved domain (domain can belong
  #     to the org, or to the parent enterprise)
  #
  # domains - VerifiableDomain's for this Organization. Will call email_eligible_domains to
  #           get the domains if parameter is not specified. Note: email_eligible_domains will
  #           load the domains, so if the caller is async, it needs to load the domains first via
  #           async_email_eligible_domains, then pass them in to here. Or if the caller has
  #           already pre-loaded the domains, it can pass them into here to skip the extra db query.
  #
  # Returns: Integer
  def members_without_eligible_email_count(domains = T.unsafe(self).email_eligible_domains)
    return 0 unless domains.any?

    member_ids_without_eligible_email(domains).count
  end

  # Public: The ids of members of this organization who do not have an email
  # address eligible to receive notifications when notifications restrictions are
  # enabled. Conditions for eligibility:
  #   - email address must be verified (Note: When GitHub.email_verification_enabled? returns
  #     false, user emails cannot be verified in the current environment. So the check for whether
  #     a user email is verified is bypassed.)
  #   - email address must from a verified or approved domain (domain can belong
  #     to the org, or to the parent enterprise)
  #
  # domains - VerifiableDomain's for this Organization. Will call email_eligible_domains to
  #           get the domains if parameter is not specified. Note: email_eligible_domains will
  #           load the domains, so if the caller is async, it needs to load the domains first via
  #           async_email_eligible_domains, then pass them in to here. Or if the caller has
  #           already pre-loaded the domains, it can pass them into here to skip the extra db query.
  #
  # Returns: Array of Integers
  def member_ids_without_eligible_email(domains = T.unsafe(self).email_eligible_domains)
    return [] unless domains.any?

    verified_condition = GitHub.email_verification_enabled? ? "state = 'verified' AND " : ""
    ids = T.unsafe(self).member_ids
    verified_ids = T.unsafe(UserEmail.where("#{verified_condition} normalized_domain IN (:domains)", domains: domains.map(&:domain))).batched_scope(:user_id, values: ids).pluck(:user_id)
    ids - verified_ids
  end

  # Public: Does this member have a verified email from a verified or approved domain
  # for this organization?
  #
  # user - The User to check.
  #
  # Returns Boolean
  def user_has_email_eligible_domain_notification_email?(user)
    return false unless user.present?

    @verified_email_results ||= {}
    return @verified_email_results[user] if @verified_email_results.key?(user)
    @verified_email_results[user] = user.eligible_emails_for(self).any?
  end

  # Public: Does the organization require a domain restriction check for this user
  #
  # Outside collaborators and non-members who are receiving notifications for
  # this organization's public repositories are exempt from notification
  # restrictions, so we shouldn't prevent delivery for these users.
  #
  # user - The User to check.
  #
  # Returns: Boolean.
  def verified_domain_restriction_should_check_user?(user)
    return user.organization_ids.include?(T.unsafe(self).id) if T.unsafe(self).business.nil?

    user.organization_ids.include?(T.unsafe(self).id) ||
      T.unsafe(self).business.admin_and_organization_member_ids(actor_ids: [user.id]).any?
  end

  # Public: Is this user able to receive email notifications for this organization or its business?
  #
  # Check if a user is restricted by the verified domain notification restrictions feature.
  # It does not check if the user is able to receive notifications for a specific repository
  # and does not do any kind of authorization checking.
  #
  # See also Newsies::Settings#email_notification_eligible_organizations
  #
  # user - The User to check.
  #
  # Returns: Boolean.
  def user_can_receive_email_notifications?(user)
    return false unless user

    # Can receive notifications if notifications aren't restricted
    return true unless T.unsafe(self).restrict_notifications_to_verified_domains?

    # Does the organization require a domain restriction check for this user
    return true unless verified_domain_restriction_should_check_user?(user)

    # Cannot receive notification if notifications are restricted and user doesn't have a verified
    # email address from a verified or approved domain for this organization or its enterprise
    return false unless user_has_email_eligible_domain_notification_email?(user)

    settings = user.newsies_settings_response
    # Return false if notification settings are unavailable
    return false unless settings.success?

    email = settings.email(self)&.address
    # Return false if no email set for receiving notifications for this organization
    return false unless email =~ User::EMAIL_REGEX

    # Is the email set to receive notifications for this organization from one of the
    # verified or approved domains?
    email_domain = email.split("@")[1]&.downcase
    T.unsafe(self).email_eligible_domain_urls.map(&:downcase).include?(email_domain)
  end

  # Public: Emails that a user can use to receive notifications from this organization.
  #
  # user - The User to get emails for.
  #
  # Returns Array[UserEmail]
  def notifiable_emails_for(user)
    return [] unless user.present?

    return user.all_notifiable_emails unless user.organization_ids.include?(T.unsafe(self).id)
    return user.all_notifiable_emails unless T.unsafe(self).restrict_notifications_to_verified_domains?

    user.eligible_emails_for(self)
  end

  # Public: Should the notification restrictions banner in this organization
  # be displayed for a specified user?
  #
  # user - The User to check.
  #
  # Returns: Boolean.
  def show_notification_restriction_banner?(user)
    return false unless GitHub.verified_domains_enabled?
    return false unless user.present?

    # Only show banner for organization members
    return false unless user.organization_ids.include?(T.unsafe(self).id)

    return false if user_can_receive_email_notifications?(user)

    settings = user.newsies_settings_response
    return false unless settings.success?

    settings.participating_email? || settings.subscribed_email?
  end

  def supports_showing_verified_domain_emails?
    async_supports_showing_verified_domain_emails?.sync
  end

  # Public: Are verified domain emails for members of this organization viewable
  #         by organization owners?
  #
  # Returns a Promise<Boolean>.
  def async_supports_showing_verified_domain_emails?
    T.unsafe(self).async_business.then do |owning_business|
      if GitHub.terms_of_service_enabled? &&
         !T.unsafe(self).terms_of_service.business_terms_of_service? &&
         !T.unsafe(self).terms_of_service.custom? &&
         owning_business.blank?
        next false
      end

      T.unsafe(self).plan_supports?(:display_verified_domain_emails)
    end
  end

  # Public: Is a viewer able to see domain emails for members of this org?
  #
  # Returns a Promise<Boolean>.
  def async_can_view_domain_emails?(actor)
    return Promise.resolve(false) unless actor.present?

    if actor.can_have_granular_permissions?
      T.unsafe(self).resources.members.async_readable_by?(actor)
    else
      T.unsafe(self).async_adminable_by?(actor)
    end
  end
end
