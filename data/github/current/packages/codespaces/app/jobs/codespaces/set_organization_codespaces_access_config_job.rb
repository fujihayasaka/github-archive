# typed: strict
# frozen_string_literal: true

class Codespaces::SetOrganizationCodespacesAccessConfigJob < CodespacesJob

  retry_on_dirty_exit
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  sig { params(organization_id: Integer, access_value: T.nilable(String), ownership_value: T.nilable(String)).void }
  def perform(organization_id:, access_value: nil, ownership_value: nil)
    organization = Organization.find_by(id: organization_id)
    return unless organization.present?

    with_write do
      ApplicationRecord::Domain::ConfigurationEntries.transaction do
        if access_value.present?
          organization.update_organization_codespaces_user_limit(access_value, actor: organization.owner)
        end

        if ownership_value.present?
          organization.update_organization_codespaces_ownership_setting(ownership_value, actor: organization.owner)
        end
      end
    end
  end
end
