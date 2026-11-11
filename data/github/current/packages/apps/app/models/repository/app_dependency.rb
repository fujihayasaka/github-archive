# typed: true
# frozen_string_literal: true

module Repository::AppDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Internal: Remove repository for all IntegrationInstallations.
  #
  # Returns nil.
  def remove_from_integration_installations(editor:, installations:, entry_point:)
    T.bind(self, Repository)

    installations.each do |installation|
      # Since the installation is on all we don't have to do anything.
      if installation.installed_on_all_repositories?
        installation.instrument_repositories_removed(
          [id],
          actor: editor,
          repository_selection: "all",
        )
        next
      end

      IntegrationInstallation::RepositoryEditor.perform(installation, action: :remove, repositories: [self], editor: editor, entry_point: entry_point)
    end
  end
end
