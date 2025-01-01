# typed: true
# frozen_string_literal: true

class AbilitiesPermissionsRouting < ApplicationRecord::Iam
  self.table_name = "abilities_permissions_routing"
  enum :cluster, [:mysql1, :moving, :collab]

  validates :subject_type, presence: true, uniqueness: { case_sensitive: false }
  validates :cluster,      presence: true, uniqueness: { scope: :subject_type }
end
