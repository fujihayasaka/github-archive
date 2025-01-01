# typed: true
# frozen_string_literal: true

class UserProgrammaticAccessGrant < ApplicationRecord::Permissions
  include ProgrammaticAccessGrantable
  include ProgrammaticAccessGrantInstrumentable

  belongs_to :target, class_name: "User", foreign_key: :user_id, required: true # rubocop:todo Rails/InverseOf

  belongs_to :user_programmatic_access,
    inverse_of: :user_programmatic_access_grants,
    required: true

  has_many :permission_records, class_name: "Permission", as: :actor
  destroy_dependents_in_background :permission_records

  has_one :request,
    class_name: "UserProgrammaticAccessGrantRequest",
    foreign_key: :user_programmatic_access_grant_id,
    inverse_of: :grant,
    dependent: :destroy

  # Overridden method from ProgrammaticActorPermissionGrantable
  def can_have_granular_user_permissions?
    user_id == user_programmatic_access&.user_id
  end
end
