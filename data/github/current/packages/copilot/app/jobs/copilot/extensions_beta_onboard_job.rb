# typed: strict
# frozen_string_literal: true

module Copilot
  class ExtensionsBetaOnboardJob < ApplicationJob
    extend T::Sig

    MAX_THROTTLE_RETRIES = 4
    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    queue_as :mailers
    retry_on_dirty_exit

    # When onbaording a business, onboard_entity will be a EarlyAccessMembership. Otherwise, it will be an array of logins
    sig { params(onboard_entity: T.any(EarlyAccessMembership, T::Array[String])).void }
    def perform(onboard_entity)
      if onboard_entity.is_a?(EarlyAccessMembership)
        # Business case
        onboard!(onboard_entity)
      else
        # Organization/User case
        users_and_orgs = ::User.where(login: onboard_entity).to_a
        memberships = T.let(EarlyAccessMembership
                              .copilot_extensions_waitlist
                              .where(member: users_and_orgs)
                              .includes(:member)
                              .index_by(&:member_id),
                            T::Hash[Integer, EarlyAccessMembership])

        users_and_orgs.each do |user_or_org|
          membership = memberships[T.must(user_or_org.id)]
          next unless membership.present?

          onboard!(membership)
        end
      end
    end

    private

    sig { params(membership: EarlyAccessMembership).void }
    def onboard!(membership)
      unless membership.can_onboard?
        log_outcome(membership, false)
        return
      end

      with_write do
        result = membership.update!(feature_enabled: true)
        if result
          send_emails(membership)
        end
        log_outcome(membership, result)
      end
    end

    sig { params(membership: EarlyAccessMembership).void }
    def send_emails(membership)
      onboarded_entity = T.cast(membership.member, T.any(::User, ::Organization, ::Business))

      case onboarded_entity
      when ::Business, ::Organization
        onboarded_entity.admins.each do |admin|
          CopilotExtensionsBetaMembershipMailer.business_waitlist_acceptance(membership, admin).deliver_later
        end
      when ::User
        CopilotExtensionsBetaMembershipMailer.individual_waitlist_acceptance(membership).deliver_later
      else
        T.absurd(onboarded_entity)
      end
    end

    sig { params(membership: EarlyAccessMembership, success: T::Boolean).void }
    def log_outcome(membership, success)
      member_data = {
        "gh.#{membership.member.class.name&.downcase}.id" => membership.member.id,
        "gh.#{membership.member.class.name&.downcase}.name" => membership.member.display_login,
      }

      if success
        GitHub.logger.info("#{membership.member.class} onboarded to Copilot Extensions Beta", member_data)
      else
        GitHub.logger.info("Failed to onboard #{membership.member.class} to Copilot Extensions Beta", member_data)
      end
    end
  end
end
