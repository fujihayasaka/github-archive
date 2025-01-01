# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :view_org_api_insights do |access|
    access.ensure_context :resource
    access.allow :org_api_insights_viewer
  end
end
