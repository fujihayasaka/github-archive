# typed: true
# frozen_string_literal: true

class OrganizationProgrammaticAccessGrantRequest < ApplicationRecord::Permissions
  include ProgrammaticAccessGrantRequestable
  include ProgrammaticAccessGrantExpirationLimitable

  belongs_to :actor,
    class_name: "User",
    foreign_key: :user_id,
    inverse_of: :requested_organization_programmatic_access_grant_requests,
    optional: false

  belongs_to :target,
    class_name: "Organization",
    foreign_key: :organization_id,
    inverse_of: :organization_programmatic_access_grant_requests,
    optional: false

  belongs_to :grant,
    class_name: "OrganizationProgrammaticAccessGrant",
    foreign_key: :organization_programmatic_access_grant_id,
    inverse_of: :request

  belongs_to :user_programmatic_access,
    inverse_of: :organization_programmatic_access_grant_requests,
    optional: false

  has_many :permission_records, class_name: "Permission", as: :actor
  destroy_dependents_in_background :permission_records

  validates_uniqueness_of :user_programmatic_access_id, allow_nil: true, scope: :organization_id
end
