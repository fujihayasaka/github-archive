# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrantRequestable
  extend ActiveSupport::Concern

  include ActiveModel::Validations
  include ProgrammaticAccessGrantable
  include ProgrammaticAccessGrantRequestInstrumentable
  include ProgrammaticAccessGrantRequestWebhookEventable
  include GitHub::UserContent

  included do
    validates :reason, length: 1..1024, allow_nil: true, allow_blank: false

    validate :validate_grant_belongs_to_target
    validate :validate_user_programmatic_access_belongs_to_actor
  end

  def approvable_by?(actor)
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    @approvable_results = {} unless defined?(@approvable_results)
    return @approvable_results[actor] if @approvable_results.key?(actor)

    @approvable_results[actor] = target.try(:pat_requests_auto_approved?)
    return true if @approvable_results[actor]

    @approvable_results[actor] = writable_by?(actor)
    return true if @approvable_results[actor]
    return @approvable_results[actor] unless actor&.user?

    # Allow approvals if downgrading or requesting the same access.
    if self.grant
      unless ProgrammaticAccessGrant::AccessLevel.from_grantable(self) > ProgrammaticAccessGrant::AccessLevel.from_grantable(self.grant)
        @approvable_results[actor] = true
      end
    end

    @approvable_results[actor]
  end

  def writable_by?(actor)
    @writable_results = {} unless defined?(@writable_results)
    return @writable_results[actor] if @writable_results.key?(actor)

    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    @writable_results[actor] =
      case target
      when Organization
        target&.resources.organization_personal_access_token_requests.writable_by?(actor)
      when User
        target == actor
      else
        false
      end
  end

  # Internal: Used for GitHub::UserContent so that we can render the 'reason'
  # as HTML.
  #
  # Returns a String.
  def body
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    self.reason
  end

  # Public: Cancel an ongoing access request with instrumentation.
  #
  # Returns a Boolean.
  def cancel
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    destroyed = self.destroy
    instrument_cancel if destroyed

    destroyed
  end

  def deny!(reason: nil)
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    extra_payload = {}
    extra_payload[:reason] = reason.blank? ? nil : reason

    self.destroy!

    instrument_deny(extra_payload)

    true
  end

  # Internal: Ensure that the grant and the target belong to the same owner.
  #
  # Returns nothing.
  def validate_grant_belongs_to_target
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    return unless grant && target
    return if target == grant&.target

    errors.add(:base, "target mismatch")
  end

  # Internal: Ensure that the actor owns the UserProgrammaticAccess so that
  # users can't request access for PATs they don't own.
  #
  # Returns nothing.
  def validate_user_programmatic_access_belongs_to_actor
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    return unless user_programmatic_access && actor
    return if user_programmatic_access&.owner == actor

    errors.add(:base, "owner mismatch")
  end
end
