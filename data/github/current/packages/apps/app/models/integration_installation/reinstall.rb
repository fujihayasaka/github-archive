# typed: strict
# frozen_string_literal: true

class IntegrationInstallation
  class Reinstall

    # Private: Reinstalls Apps that need to be transferred over to the new_owner
    sig do
      params(
        repository: Repositories::IRepository,
        new_owner: User,
        integrations: T::Array[Integration],
        entry_point: Symbol,
      ).void
    end
    def self.on_repository(repository:, new_owner:, integrations:, entry_point:)
      integrations.each do |integration|
        result = if (current_installation = integration.installations.with_target(new_owner).first)
          IntegrationInstallation::Editor.append(current_installation, repositories: [repository], editor: new_owner, entry_point: entry_point)
        else
          installer = new_owner.organization? ? new_owner.admins.first : new_owner
          integration.install_on(
            new_owner, repositories: [repository], installer: installer, reinstalling_during_repository_transfer: true, entry_point: entry_point
          )
        end
        status = result.success? ? "succeeded" : "failed"
        GitHub.dogstats.increment("repository.reinstall_integration", tags: ["result:#{status}"])
      end
    end
  end
end
