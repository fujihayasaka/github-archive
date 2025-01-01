# typed: true
# frozen_string_literal: true

class UpdateOrganizationTeamPrivacyJob < ApplicationJob
  queue_as :update_organization_team_privacy

  retry_on StandardError

  def perform(organization_id, privacy, opts = {})
    @organization_id = organization_id
    @privacy         = privacy.to_sym

    with_write { organization.update_team_privacy!(@privacy) }
  end

  private

  def organization
    @organization ||= Organization.find(@organization_id)
  end

end
