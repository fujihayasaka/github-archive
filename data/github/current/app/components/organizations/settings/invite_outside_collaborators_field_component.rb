# typed: true
# frozen_string_literal: true

module Organizations
  module Settings
    # Started as an extraction from the Orgs::Settings::MemberPrivilegesView
    # to make for more concise testing
    class InviteOutsideCollaboratorsFieldComponent < ApplicationComponent
      include EnterpriseManagedUsersHelper

      attr_reader :organization

      def initialize(organization:)
        @organization = organization
      end

      def invite_setting_enabled?
        if organization.enterprise_managed_user_enabled?
          # there is no policy set at the enterprise level. If any policy is set, the organization admins cannot
          # override it.
          !organization.business.members_can_invite_outside_collaborators_policy? && organization.business.feature_enabled?(:emu_repository_policies_enabled)
        else
          # there is no policy set at the organization level
          !organization.members_can_invite_outside_collaborators_policy?
        end
      end

      def outside_collaborator_policy_text
        if organization.members_can_invite_outside_collaborators?
          "Repository administrators can invite outside collaborators."
        elsif organization.enterprise_admins_only_can_invite_outside_collaborators?
          "Inviting outside collaborators has been disabled."
        else
          "Repository administrators cannot invite outside collaborators."
        end
      end

      def collaborator_docs_href
        ghec = organization.enterprise_managed_user_enabled? && organization.business.feature_enabled?(:emu_repository_policies_enabled)
        DocsUrlConfig.url_for(
          "organizations/adding-outside-collaborators-to-repositories-in-your-organization",
          ghec:
        )
      end
    end
  end # Settings
end # Organizations
