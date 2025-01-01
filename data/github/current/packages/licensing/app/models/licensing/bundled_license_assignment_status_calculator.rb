# typed: true
# frozen_string_literal: true

module Licensing
  class BundledLicenseAssignmentStatusCalculator
    PRIORITIZED_STATUSES = [
      :license_revoked,
      :assignment_linked_to_user,
      :invited_to_org,
      :invited_to_repo,
      :declined_org_invite,
      :declined_repo_invite,
      :linked_to_enterprise_account,
      :pending_account_setup
    ]

    def self.calculate_highest_priority(assignment, requested_status: nil)
      new(assignment).calculate(requested_status: requested_status)
    end

    def initialize(assignment)
      @assignment = assignment
    end

    def calculate(requested_status:)
      derived_status = case
      when assignment.revoked?
        :license_revoked
      when assignment.user_id.present?
        :assignment_linked_to_user
      when has_organization_invitation?
        :invited_to_org
      when has_repository_invitation?
        :invited_to_repo
      when assignment.business_id.present?
        :linked_to_enterprise_account
      when assignment.business_id.nil?
        :pending_account_setup
      end

      highest_priority(derived_status, requested_status)
    end

    private

    attr_reader :assignment

    def has_organization_invitation?
      assignment.business.present? &&
        assignment.business.pending_member_invitations.exists?(email: assignment.email)
    end

    def has_repository_invitation?
      assignment.business.present? &&
        assignment.business.pending_collaborator_invitations.exists?(email: assignment.email)
    end

    def highest_priority(derived_status, requested_status)
      return derived_status if requested_status.blank?

      [derived_status, requested_status].sort_by { |status| T.must(PRIORITIZED_STATUSES.index(status)) }.first
    end
  end
end
