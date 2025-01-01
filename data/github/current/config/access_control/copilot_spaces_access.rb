# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl

  # The resource is the organization owning copilot space
  # If the owner is an organization, any user who is a member of the org
  # can view a copilot space the org owns
  define_access :get_organization_copilot_space do |access|
    access.ensure_context :resource
    access.allow(:org_copilot_space_viewer) { |context| context[:resource].try(:organization?) }
  end
end
