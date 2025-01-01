# typed: true
# frozen_string_literal: true

class OrganizationProgrammaticAccessGrant < ApplicationRecord::Permissions
  include ProgrammaticAccessGrantable
  include ProgrammaticAccessGrantInstrumentable
  include ProgrammaticAccessGrantExpirationLimitable

  # Optional attribute to store revoke reason temporarily
  attr_accessor :revoke_reason

  belongs_to :target,
    class_name: "Organization",
    foreign_key: :organization_id,
    inverse_of: :organization_programmatic_access_grants,
    required: true

  belongs_to :user_programmatic_access,
    inverse_of: :organization_programmatic_access_grants,
    required: true

  has_many :permission_records, class_name: "Permission", as: :actor
  destroy_dependents_in_background :permission_records

  has_one :request,
    class_name: "OrganizationProgrammaticAccessGrantRequest",
    foreign_key: :organization_programmatic_access_grant_id,
    inverse_of: :grant,
    dependent: :destroy
end
