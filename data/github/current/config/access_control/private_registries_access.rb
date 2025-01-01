# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :read_org_private_registries do |access|
    access.ensure_context :resource, :user
    access.allow :org_private_registries_reader
  end

  define_access :write_org_private_registries do |access|
    access.ensure_context :resource, :user
    access.allow :org_private_registries_writer
  end
end
