# typed: true
# frozen_string_literal: true

# An OauthApplicationApproval represents the approval status for allowing a
# specific OauthApplication to access the resources of a specific Organization.
#
# If an Organization is using an application approval list, only approved
# applications are allowed to access the Organization's
# resources. The state of the OauthApplicationApproval determines whether a
# specific application has been approved by the Organization.
class OauthApplicationApproval < ApplicationRecord::Domain::Users # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include GitHub::UTF8
  include Instrumentation::Model

  validate :org_can_block_app, if: :blocked?

  # Public: The Organization that is considering approval for the application.
  belongs_to :organization

  # Public: The OauthApplication that is being considered for approval.
  belongs_to :application, class_name: "OauthApplication"

  # Public: The User that requested the organization to approve the application.
  belongs_to :requestor, class_name: "User"

  validates_presence_of :organization
  validates_presence_of :application
  validates_presence_of :requestor, on: :create

  # Public: Integer state of this approval.
  # column :state
  enum :state, { pending_approval: 0, approved: 1, denied: 2, blocked: 3 }

  # Public: String reason this application is allowed.
  def reason
    utf8(read_attribute(:reason))
  end

  private

  def org_can_block_app
    return unless application.present? && organization.present?

    # Only organizations that have first-party OAuth app restrictions enabled can block
    org_can_block = T.must(organization).first_party_oauth_app_restrictions_enabled?

    return if T.must(application).blockable_client_app? && org_can_block

    errors.add(:application, "cannot be blocked")
  end
end
