# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrantInstrumentable
  extend ActiveSupport::Concern
  extend T::Helpers

  include Instrumentation::Model

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))
    after_destroy_commit :instrument_deletion
  end

  # Used as default payload for instrumentation.
  def event_payload
    T.bind(self, T.any(OrganizationProgrammaticAccessGrant, UserProgrammaticAccessGrant))

    payload = {
      user_programmatic_access_id: user_programmatic_access_id,
      user_programmatic_access_name: user_programmatic_access_attrs[:name],
      repository_selection: self.repository_selection,
      requester: user_programmatic_access_attrs[:owner_name],
      requester_id: user_programmatic_access_attrs[:owner_id],
      target: target&.display_login,
      target_id: target&.id,
      permissions: self.permissions,
      token_id: user_programmatic_access_id,
    }.merge(event_payload_for_target)

    if self.repository_selection == ProgrammaticAccessGrant::RepositorySelection::SUBSET.to_s
      payload[:repositories] = self.repositories.pluck(:id)
    end

    payload
  end

  def instrument_granting(payload = {})
    payload[:prefix] = "personal_access_token"
    instrument :access_granted, payload
  end

  def instrument_deletion(payload = {})
    payload[:prefix] = "personal_access_token"
    payload[:reason] = @revoke_reason
    instrument :access_revoked, payload
  end

  def user_programmatic_access_attrs
    T.bind(self, T.any(OrganizationProgrammaticAccessGrant, UserProgrammaticAccessGrant))

    attrs = {
      name: T.let(nil, T.nilable(String)),
      owner_name: T.let(nil, T.nilable(String)),
      owner_id: T.let(nil, T.nilable(Integer)),
    }

    if user_programmatic_access.present?
      attrs[:name] = T.must(user_programmatic_access).name
      attrs[:owner_name] = T.must(user_programmatic_access&.owner).display_login
      attrs[:owner_id] = T.must(user_programmatic_access&.owner).id

      return attrs
    end

    cached_name_key = UserProgrammaticAccess::CACHED_ATTRS_KEY_TEMPLATE % user_programmatic_access_id
    attrs_as_json = Apps::KV.store.get(cached_name_key).value { "{}" }

    JSON.parse(attrs_as_json).symbolize_keys
  end

  def event_payload_for_target
    T.bind(self, T.any(OrganizationProgrammaticAccessGrant, UserProgrammaticAccessGrant))

    case target
    when Organization
      payload = {
        organization_programmatic_access_grant_id: id,
        org: T.must(target).display_login,
        org_id: T.must(target).id,
        user: user_programmatic_access_attrs[:owner_name],
        user_id: user_programmatic_access_attrs[:owner_id],
      }

      if (business = T.must(self.target).business)
        payload[:business] = business.slug
        payload[:business_id] = business.id
      end

      payload
    when User
      {
        user_programmatic_access_grant_id: id,
        user: T.must(target).display_login,
        user_id: T.must(target).id,
      }
    else
      # target may have been hard-deleted; fall back to foreign key so the audit log still captures the target ID.
      if is_a?(OrganizationProgrammaticAccessGrant)
        {
          organization_programmatic_access_grant_id: id,
          org: nil,
          org_id: organization_id,
          target: nil,
          target_id: organization_id,
          user: user_programmatic_access_attrs[:owner_name],
          user_id: user_programmatic_access_attrs[:owner_id],
        }
      elsif is_a?(UserProgrammaticAccessGrant)
        # The target is the token owner, so we can recover their display name from the KV cache
        {
          user_programmatic_access_grant_id: id,
          target: user_programmatic_access_attrs[:owner_name],
          target_id: user_id,
          user: user_programmatic_access_attrs[:owner_name],
          user_id: user_id
        }
      else
        {}
      end
    end
  end
end
