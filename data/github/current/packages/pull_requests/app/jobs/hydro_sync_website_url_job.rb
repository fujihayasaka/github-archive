# typed: true
# frozen_string_literal: true

class HydroSyncWebsiteUrlJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_sync_website_url

  # Public: process a Hydro message for github.repositories.v1.Renamed
  # and github.repositories.v1.Transferred events.
  #
  # When a repository is renamed or transferred, if the repository's homepage
  # was set to the GitHub Pages URL (via the "Use your GitHub Pages website"
  # setting), update it to the new pages URL.
  sig { void }
  def perform
    page = repository.page
    return unless page

    return unless repository.pages_url_sidebar_section_enabled?

    new_url = page.url.to_s
    return if repository.homepage.to_s == new_url

    with_write do
      unless repository.update(homepage: new_url)
        GitHub.logger.error(
          "HydroSyncWebsiteUrlJob: failed to update homepage",
          repository_id: repository_id,
          errors: repository.errors.full_messages,
        )
      end
    end
  end
end
