# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrantRequestInstrumentable
  include Instrumentation::Model

  # Internal: Used as default payload for instrumentation.
  #
  # Returns a Hash.
  def event_payload
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    payload = {
      user_programmatic_access_id: user_programmatic_access_id,
      user_programmatic_access_name: user_programmatic_access&.name,
      user_programmatic_access_request_id: self.id,
      requester: self.actor&.display_login,
      requester_id: self.actor&.id,
      target: self.target&.display_login,
      target_id: self.target&.id,
      token_id: user_programmatic_access_id,
    }.merge

    payload.merge!(permissions_difference)

    case self
    when OrganizationProgrammaticAccessGrantRequest
      payload[:org] = payload[:target]
      payload[:org_id] = payload[:target_id]

      if (business = self.target&.business)
        payload[:business] = business.slug
        payload[:business_id] = business.id
      end

      payload[:organization_programmatic_access_grant_id] = \
        organization_programmatic_access_grant_id
    when UserProgrammaticAccessGrantRequest
      payload[:user] = payload[:target]
      payload[:user_id] = payload[:target_id]

      payload[:user_programmatic_access_grant_id] = \
        user_programmatic_access_grant_id
    end

    payload[:repository_selection] = self.repository_selection

    if self.repository_selection == ProgrammaticAccessGrant::RepositorySelection::SUBSET.to_s
      payload[:repositories] = self.repositories.pluck(:id)
    end

    payload
  end

  # Public: Instrument canceling a request.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_cancel(payload = {})
    payload[:prefix] = "personal_access_token"
    instrument :request_cancelled, payload
  end

  # Public: Instrument denying a request.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_deny(payload = {})
    payload[:prefix] = "personal_access_token"
    instrument :request_denied, payload
  end

  # Public: Instrument request creation.
  #
  # Note that creation is not instrumented via after_create/after_create_commit callbacks
  # but called directly from ProgrammaticAccessGrantRequest::Service#create as permissions
  # are needed in the payload.
  #
  # payload - Hash of custom payload data.
  #
  # Returns nothing.
  def instrument_creation(payload = {})
    payload[:prefix] = "personal_access_token"
    instrument :request_created, payload
  end

  def permissions_difference
    T.bind(self, T.any(OrganizationProgrammaticAccessGrantRequest, UserProgrammaticAccessGrantRequest))

    previous_permissions = grant.try(:permissions) || {}

    differ = PermissionsDiffer.new(
      previous_permissions: previous_permissions,
      new_permissions: self.permissions
    )

    {
      permissions_added: differ.added_permissions.transform_values(&:to_s),
      permissions_upgraded: differ.upgraded_permissions.transform_values(&:to_s),
      permissions_unchanged: differ.unchanged_permissions.transform_values(&:to_s),
    }
  end
end
