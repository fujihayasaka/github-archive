# typed: true
# frozen_string_literal: true

module User::ProgrammaticAccessDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(User))

    # Do not use this relation directly! This is to help Rails build
    # the AR relationships accordingly.
    has_many :user_programmatic_accesses,
      class_name: "UserProgrammaticAccess",
      inverse_of: :owner,
      dependent: :destroy

    has_many :user_programmatic_access_grant_requests,
      class_name: "UserProgrammaticAccessGrantRequest",
      inverse_of: :target

    has_many :requested_user_programmatic_access_grant_requests,
      class_name: "UserProgrammaticAccessGrantRequest",
      inverse_of: :actor

    has_many :requested_organization_programmatic_access_grant_requests,
      class_name: "OrganizationProgrammaticAccessGrantRequest",
      inverse_of: :actor
  end
end
