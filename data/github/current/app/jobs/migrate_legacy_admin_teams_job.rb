# typed: true
# frozen_string_literal: true

class MigrateLegacyAdminTeamsJob < ApplicationJob
  queue_as :migrate_legacy_admin_teams

  retry_on StandardError

  def perform(organization_id, opts = {})
    @organization_id = organization_id

    with_write { organization.migrate_legacy_admin_teams! }
  end

  private

  def organization
    @organization ||= Organization.find(@organization_id)
  end
end
