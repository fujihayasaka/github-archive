# typed: true
# frozen_string_literal: true

module Sso
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :target
    attr_reader :member
    attr_reader :linked_identity_list

    def page_title
      if member.is_a?(::User) && member.type == Organization.to_s
        "#{ member }'s linked identity details"
      else
        "#{ member }'s single sign-on details"
      end
    end

    def external_sessions
      return SAML::Session.active.where(user_id: member&.id) if GitHub.enterprise?

      external_identity&.sessions&.active&.with_user_session || []
    end

    def user_sessions(external_session)
      return external_session.user.sessions.unexpired.unrevoked if GitHub.enterprise?

      [external_session.user_session]
    end

    def external_identity
      return nil unless cloud_member?

      return @external_identity if defined?(@external_identity)

      provider = if emu_oidc_target?(target: target.external_identity_session_owner)
        target.external_identity_session_owner.external_provider
      else
        target.external_identity_session_owner.saml_provider
      end

      @external_identity = provider&.external_identities&.linked_to(member)&.first
    end

    def allow_revoke_actions?
      return false unless user_identity?
      return true if target.is_a?(Business)
      return true if target.business&.owner?(current_user)
      !target.business&.external_provider_enabled?
    end

    #  check feature flag state on a target
    def emu_oidc_target?(target:)
      target.present? && target.is_a?(Business) && target.oidc_enabled?
    end

    def cloud_member?
      member.is_a?(User)
    end

    def user_identity?
      !cloud_member? || member&.type == User.to_s
    end

    def scim_identity?
      return false if external_identity.nil?

      external_identity.scim_user_data.any?
    end

    def authorized_credentials
      return [] unless user_identity?

      @authorized_credentials ||=
      begin
        authorized_tokens = authorized_credentials_scope.select(&:using_personal_access_token?)
        authorized_keys = authorized_credentials_scope.select(&:using_public_key?)
        credentials = (authorized_tokens + authorized_keys).map(&:credential).compact

        if target_is_enterprise_managed_business?
          credentials = credentials.uniq
        end

        credentials
      end
    end

    def target_description
      return "organization" if target.is_a?(Organization)
      "enterprise account"
    end

    def revoke_token_warning
      organization_message = if target.is_a?(Organization)
        "this organization’s private resources"
      else
        "private resources of organizations that belong to this enterprise account"
      end

      "Any applications or scripts using this token will no longer be able to access #{organization_message}. You cannot undo this action."
    end

    def unlink_identity_path
      if target.is_a?(Organization)
        urls.org_person_unlink_identity_path(target, member)
      else
        urls.enterprise_person_unlink_identity_enterprise_path(target, member)
      end
    end

    def user_sso_identity_path(user)
      return nil unless user.present?

      urls.enterprise_person_sso_enterprise_path(target, user)
    end

    def identity_primary_name(identity)
      return identity.user&.display_login if identity.user&.display_login&.present?
      return identity.scim_user_data.display_name if identity.scim_user_data.display_name.present?
      identity.scim_user_data.email
    end

    def identity_secondary_name(identity)
      display_name = identity.scim_user_data.display_name
      return display_name if display_name.present? && identity_primary_name(identity) != display_name
      return identity.scim_user_data.user_name if identity.scim_user_data.user_name.present?
      nil
    end

    def revoke_sso_session_path(session_id)
      if target.is_a?(Organization)
        urls.org_person_revoke_sso_session_path(target, member, session_id)
      else
        urls.enterprise_person_revoke_sso_session_enterprise_path(target, member, session_id)
      end
    end

    def revoke_credential_path(token, credential_type)
      if target.is_a?(Organization)
        urls.org_person_revoke_sso_token_path(target, member, token, credential_type: credential_type)
      else
        urls.enterprise_person_revoke_sso_token_enterprise_path(target, member, token, credential_type: credential_type)
      end
    end

    def external_identity_group_ids(group_data: external_identity&.saml_group_data, display_limit: 5)
      return [] unless target.is_a?(Business) && user_identity?

      group_ids = Platform::Provisioning::GroupsUserDataWrapper.new(group_data).groups

      return group_ids unless group_ids.length > display_limit
      extra_count = group_ids.length - display_limit
      group_ids = group_ids.slice(0, display_limit)
      group_ids << "#{extra_count} more..."
    end

    def external_identity_members(display_limit: 5)
      return [] unless target.is_a?(Business) && !user_identity?
      return [] if external_identity.nil?

      members = external_identity.scim_group_data.
                                  fetch_all("members").
                                  map { |attr| attr["value"] }

      return members unless members.length > display_limit
      extra_count = members.length - display_limit
      members = members.slice(0, display_limit)
      members << "#{extra_count} more..."
    end

    private

    def authorized_credentials_scope
      return Organization::CredentialAuthorization.none unless cloud_member?

      authorizations = Organization::CredentialAuthorization.
        by_actor(actor: member).
        active

      unless target_is_enterprise_managed_business?
        authorizations = authorizations.by_organization(organization: organizations)
      end

      authorizations
    end

    def organizations
      return [target] if target.is_a?(Organization)

      @organizations ||= (target.organizations.to_a & current_user.owned_organizations)
    end

    def target_is_enterprise_managed_business?
      target.is_a?(Business) && target.enterprise_managed_user_enabled?
    end
  end
end
