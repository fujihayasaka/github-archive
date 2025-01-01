# typed: true
# frozen_string_literal: true

class Organizations::Settings::Releases::RepositoriesComponent < ApplicationComponent
  attr_reader :organization
  attr_reader :selected_repo_ids
  attr_reader :form_id
  attr_reader :aria_id_prefix

  def initialize(organization:, selected_repo_ids:, form_id:, aria_id_prefix:)
    @organization = organization
    @selected_repo_ids = selected_repo_ids
    @aria_id_prefix = aria_id_prefix
    @form_id = form_id
  end

  sig { returns(String) }
  def repository_items_url
    org_releases_repositories_path(organization, page: 1)
  end
end
