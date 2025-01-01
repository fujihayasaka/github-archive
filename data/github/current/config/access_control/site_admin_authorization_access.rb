# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :site_admin_authorization do |access|
    access.ensure_context :resource
    access.ensure_context :user
    access.ensure_context :permission

    access.allow :site_admin
    access.allow :actor_with_fine_grained_permission
  end
end
