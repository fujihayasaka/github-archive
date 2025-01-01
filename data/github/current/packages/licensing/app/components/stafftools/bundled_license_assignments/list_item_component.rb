# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class Stafftools::BundledLicenseAssignments::ListItemComponent < ApplicationComponent
  include Stafftools::LicensingHelper

  def initialize(assignment:)
    @assignment = assignment
  end

  def label
    if @assignment.assigned_user?
      link_to @assignment.user.login, stafftools_user_path(@assignment.user)
    else
      link_to @assignment.email, stafftools_bundled_license_assignment_for_email_audit_log_path(@assignment.email, current_user)
    end
  end

  def icon
    if @assignment.assigned_user?
      render GitHub::AvatarComponent.new(actor: @assignment.user, size: 32)
    else
      octicon("mail", height: 32, class: "avatar")
    end
  end

  def linked_status
    @assignment.assigned_user? ? "linked" : "unlinked"
  end

  def revoked_status
    @assignment.revoked? ? "revoked" : "non-revoked"
  end

  def show_perform_link_button
    return false if !@assignment.assigned_business? || @assignment.revoked?
    true
  end
end
