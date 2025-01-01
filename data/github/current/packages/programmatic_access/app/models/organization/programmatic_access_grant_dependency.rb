# typed: true
# frozen_string_literal: true

module Organization::ProgrammaticAccessGrantDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationRecord::Base))

    # Do not use this relation directly! This is to help Rails build
    # the AR relationships accordingly.
    #
    # Please use: ProgrammaticAccessGrant.with_target(organization)
    has_many :organization_programmatic_access_grants, inverse_of: :target, dependent: :destroy
    has_many :organization_programmatic_access_grant_requests, inverse_of: :target, dependent: :destroy
  end

  def revoke_org_programmatic_access_grants_if_demoted_from_admin(user, previous_action)
    return unless previous_action == :admin
    # If this feature flag is enabled, we will not revoke the grants. If everything goes well, this flag and the method
    # will be removed.
    # See: https://github.com/github/ecosystem-apps/issues/3909
    return if user.feature_enabled?(:skip_org_pat_grant_removal_when_demoting_admin)

    # Revoke programmatic access grants when an admin is demoted
    RevokeOrgMemberProgrammaticAccessGrantsJob.perform_later(self, user)
  end
end
