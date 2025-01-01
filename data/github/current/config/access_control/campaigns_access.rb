# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :read_campaign do |access|
    access.ensure_context :resource
    access.allow :org_campaigns_api_reader
  end

  define_access :write_campaign do |access|
    access.ensure_context :resource
    access.allow :org_campaigns_api_writer
  end
end
