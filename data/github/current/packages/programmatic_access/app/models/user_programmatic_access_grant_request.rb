# typed: true
# frozen_string_literal: true

class UserProgrammaticAccessGrantRequest < ApplicationRecord::Permissions
  include ProgrammaticAccessGrantRequestable
  include ProgrammaticAccessGrantExpirationLimitable

  belongs_to :actor,
    class_name: "User",
    inverse_of: :requested_user_programmatic_access_grant_requests,
    optional: false

  belongs_to :target,
    class_name: "User",
    inverse_of: :user_programmatic_access_grant_requests,
    optional: false

  belongs_to :grant,
    class_name: "UserProgrammaticAccessGrant",
    foreign_key: :user_programmatic_access_grant_id,
    inverse_of: :request

  belongs_to :user_programmatic_access,
    inverse_of: :user_programmatic_access_grant_requests,
    optional: false

  has_many :permission_records, class_name: "Permission", as: :actor
  destroy_dependents_in_background :permission_records

  validates_uniqueness_of :user_programmatic_access_id, allow_nil: true, scope: :target_id
end
