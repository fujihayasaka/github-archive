# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  # Checks fine grained permission
  define_access :write_elm_exporter_secrets_org do |access|
    access.ensure_context :resource
    access.allow :organization_elm_exporter_secrets_writer
  end

  # Checks fine grained permission
  define_access :read_elm_exporter_secrets_org do |access|
    access.ensure_context :resource
    access.allow :organization_elm_exporter_secrets_reader
  end
end
