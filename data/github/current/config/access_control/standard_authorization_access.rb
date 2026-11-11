# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :standard_authorization do |access|
    access.ensure_context :resource
    access.ensure_context :user
    access.ensure_context :permission

    access.allow :actor_with_fine_grained_permission
  end
end
