# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::OrganizationAccessDetailComponent < ApplicationComponent

  sig { returns(Copilot::Organization) }
  attr_reader :copilot_organization

  sig { returns(::Organization) }
  attr_reader :organization

  sig { returns(String) }
  attr_reader :coding_agent_enablement_setting

  sig { params(organization: ::Organization, coding_agent_enablement_setting: String).void }
  def initialize(organization:, coding_agent_enablement_setting:)
    @organization         = organization
    @copilot_organization = T.let(Copilot::Organization.new(organization), Copilot::Organization)
    @coding_agent_enablement_setting = T.let(coding_agent_enablement_setting, String)
  end
end
