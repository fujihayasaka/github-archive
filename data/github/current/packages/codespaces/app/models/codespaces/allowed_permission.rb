# typed: true
# frozen_string_literal: true

module Codespaces
  class AllowedPermission < ApplicationRecord::Domain::Codespaces
    self.table_name = "codespace_allowed_permissions"
    self.strict_loading_by_default = true

    belongs_to :user, strict_loading: false
    include ::Repositories::BelongsToRepository
    flagged_belongs_to_repository_via_domain strict_loading: false
    belongs_to :target, polymorphic: true

    validates :repository, :user, :target_id, :action, presence: true
    validates :resource, presence: true, length: { maximum: 48 }, inclusion: { in: ::Repository::Resources::PUBLIC_SUBJECT_TYPES, message: "must be a valid resource" }
    validates :target_type, inclusion: { in: %w[Repository User], message: "must be a valid target type" }

    enum :action, { read: 0, write: 1, admin: 2 }
  end
end
