# typed: true
# frozen_string_literal: true

class Organizations::Settings::RepositoryItemsComponent < ApplicationComponent
  def initialize(organization:, repositories:, selected_repositories:, current_page:, total_count:, data_url:, aria_id_prefix:, repository_identifier_key: :global_relay_id, form_id: nil)
    @organization = organization
    @repositories = repositories
    @selected_repositories = selected_repositories
    @show_next_page = current_page * Orgs::RepositoryItemsHelper::PER_PAGE < total_count
    @data_url = data_url
    @current_page = current_page
    @aria_id_prefix = aria_id_prefix
    @repository_identifier_key = repository_identifier_key
    @form_id = form_id
  end

  def first_page?
    @current_page <= 1
  end

  def render?
    @show_next_page || @repositories.any?
  end

  def identifier_for(repository)
    case @repository_identifier_key
    when :id, "id"
      repository.id
    else
      repository.global_relay_id
    end
  end

  def visibility_for(repository)
    repository.visibility.capitalize
  end
end
