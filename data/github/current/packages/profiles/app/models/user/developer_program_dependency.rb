# typed: false
# frozen_string_literal: true

module User::DeveloperProgramDependency
  extend ActiveSupport::Concern

  included do
    # Public: Membership in the developer program (optional).
    has_one :developer_program_membership, dependent: :destroy
  end

  # Public: Boolean if this user is a member of an organization that has joined
  # the GitHub Developer Program.
  #
  # Returns truthy if user belongs to an org with Developer Program membership.
  # Returns false for Organizations.
  def member_of_developer_program_organization?
    return false if organization?

    @member_of_developer_program_organization ||= begin
      organizations.any? { |o| o.developer_program_member? }
    end
  end

  # Public: Boolean flag if this user (or org) is a member of the GitHub
  # Developer Program?
  #
  # Returns truthy if the user (or org) is a member of the GitHub
  # Developer Program.
  def developer_program_member?
    developer_program_membership &&
      !developer_program_membership.new_record? &&
      developer_program_membership.active?
  end

  # Public: Indicates if we should display the developer program badge on this
  #         user's profile.
  #
  # Returns a Boolean.
  def show_developer_program_badge?
    return false if GitHub.enterprise?
    return false if employee?

    developer_program_member?
  end
end
