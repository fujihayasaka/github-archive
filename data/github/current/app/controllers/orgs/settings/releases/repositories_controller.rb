# typed: true
# frozen_string_literal: true

class Orgs::Settings::Releases::RepositoriesController < Orgs::Controller
  include Orgs::RepositoryItemsHelper

  before_action :org_admins_only

  depends_on_clusters ApplicationRecord::Mysql1,
   ApplicationRecord::IamAbilities,
   ApplicationRecord::Repositories,
   ApplicationRecord::Configurations,
   only: [:index, :edit]

  FORM_ID = Organizations::Settings::Releases::PolicyComponent::REPOSITORIES_FORM_ID
  ARIA_PREFIX = "immutable-release-repo"

  # Renders a paginated list of repositories for the organization
  def index
    render(Organizations::Settings::RepositoryItemsComponent.new(
      organization: current_organization,
      repositories: additional_repositories(Set.new),
      selected_repositories: immutability_enforced_repo_ids,
      current_page: page,
      total_count: current_organization.repositories.size,
      data_url: org_releases_repositories_path(current_organization, page: page + 1),
      form_id: FORM_ID,
      aria_id_prefix: ARIA_PREFIX,
      repository_identifier_key: :id,
    ), layout: false)
  end

  # Renders the dialog for selecting the set of organization repositories for which immutable releases should be
  # enforced.
  #
  # This dialog is loaded asynchronously from the Organizations::Settings::Releases::PolicyComponent.
  def edit
    render(Organizations::Settings::Releases::RepositoriesComponent.new(
      organization: current_organization,
      selected_repo_ids: immutability_enforced_repo_ids,
      form_id: FORM_ID,
      aria_id_prefix: ARIA_PREFIX
    ), layout: false)
  end

  # Receives the form submission for the repository selection dialog with lists of repository IDs which should either
  # be enforced or unenforced for immutable releases.
  def update
    ids_to_enforce = params[:enable] || []
    ids_to_unenforce = params[:disable] || []

    begin
      if ids_to_enforce.any?
        org_config.enforce_immutable_releases_for_repo_ids(ids_to_enforce, actor: current_user)
      end

      if ids_to_unenforce.any?
        org_config.unenforce_immutable_releases_for_repo_ids(ids_to_unenforce, actor: current_user)
      end

      flash[:notice] = "Selected repositories for immutable releases enforcement were updated."
    rescue ActiveRecord::ActiveRecordError => e
      flash[:error] = "Failed to update selected repositories for immutable releases enforcement: #{e.message}"
    end

    redirect_to settings_org_repo_defaults_path(current_organization)
  end

  private

  sig { returns(Releases::ImmutableOrganizationConfig) }
  memoize def org_config
    Releases::ImmutableOrganizationConfig.new(current_organization)
  end

  def immutability_enforced_repo_ids
    org_config.immutable_releases_enforced_repo_ids
  end
end
