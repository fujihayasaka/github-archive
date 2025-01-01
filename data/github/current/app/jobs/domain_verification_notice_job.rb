# typed: true
# frozen_string_literal: true
class DomainVerificationNoticeJob < ApplicationJob
  queue_as :mailers

  def perform(owner, allowed_domain, state)
    members = ActiveRecord::Base.connected_to(role: :reading) do
      # Getting the member IDs in a separate query is better for performance.
      User.where(id: member_ids(owner)).
        joins(:emails).
        where("
                    user_emails.normalized_domain = :domain
                    AND user_emails.state = 'verified'
                  ", domain: allowed_domain).
        distinct
    end

    members.each do |member|
      case owner
      when Organization
        OrganizationMailer.domain_verification_notice(
          member,
          owner,
          allowed_domain,
          state
        ).deliver_later
      when Business
        BusinessMailer.domain_verification_notice(
          member,
          owner,
          owner.organization_logins_for_member(member, member_ids: member_ids(owner)),
          allowed_domain,
          state
        ).deliver_later
      end
    end
  end

  def member_ids(owner)
    return @member_ids if defined?(@member_ids)
    @member_ids = case owner
    when Organization
      owner.member_ids
    when Business
      owner.organization_member_ids
    end
  end
end
