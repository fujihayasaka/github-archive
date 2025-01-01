# typed: true
# frozen_string_literal: true

class Organizations::Settings::RepositorySelectionComponent < ApplicationComponent
  def initialize(organization:, repositories:, selected_repositories: , total_count: nil, data_url:, aria_id_prefix:, discard_changes_on_close: false, repository_identifier_key: :global_relay_id)
    @organization = organization
    @repositories = repositories
    @selected_repositories = selected_repositories || []
    @total_count = total_count || organization.repositories.size
    @data_url = data_url
    @aria_id_prefix = aria_id_prefix
    @discard_changes_on_close = discard_changes_on_close
    @repository_identifier_key = repository_identifier_key
  end
end
