# typed: true
# frozen_string_literal: true

module Repository::InstallationsDependency
  extend T::Helpers

  requires_ancestor { Repository }

  def instrument_repo_added_to_installations_across_all_repositories(actor: created_by)
    T.bind(self, Repository)

    return true if advisory_workspace?
    if installations_on_all = T.must(owner).installations_on_all_repositories
      installations_on_all.each do |installation|
        options = {
          actor: actor,
          repository_selection: "all"
        }
        installation.instrument_repositories_added([self.id], **options)
      end
    end
  end

  def instrument_repo_removed_from_installations
    T.bind(self, Repository)

    return true unless owner.present?
    return true if advisory_workspace?
    if installations = IntegrationInstallation.with_repository(self)
      installations.each do |installation|
        selection = installation.installed_on_all_repositories? ? "all" : "selected"
        installation.instrument :repositories_removed, actor: deleted_by, repositories_removed: [self.id], repositories_removed_names: [self.full_name], repository_selection: selection
      end
    end
  end
end
