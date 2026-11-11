# typed: true
# frozen_string_literal: true

class BranchAuthorizationController < AbstractRepositoryController
  before_action :login_required
  before_action :check_permissions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:authorized_actor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:authorized_actor, :suggestions], optional: true

  VALID_TYPES = %w[push dismiss bypass_pr bypass_fp].freeze
  VALID_ACTOR_TYPES = %w[user team app].freeze

  def authorized_actor # rubocop:todo GitHub/UseRestfulActions
    actor_type, actor_id = params[:item]&.split("/", 2)
    return head 404 unless VALID_TYPES.include?(params[:type])
    return head 404 unless VALID_ACTOR_TYPES.include?(actor_type)

    actor =
      case actor_type
      when "user"
        User.find_by(id: actor_id)
      when "team"
        Team.find_by(id: actor_id)
      when "app"
        IntegrationInstallation.with_repository(current_repository).
          includes(:integration).joins(:integration).
          where(integrations: { id: actor_id }).first
      end

    filtered_actor = filter_write_actors([actor]).first
    return head 404 if filtered_actor.nil?

    respond_to do |format|
      format.html do
        render partial: "branch_authorization/authorized_actor", locals: {
          actor: filtered_actor,
          form_field_name: params[:type],
        }
      end
    end
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    autocompleteQuery = AutocompleteQuery.new(current_user, params[:q],
      organization: current_repository.organization,
      repository: current_repository,
      include_teams: true,
      include_integration_installations: include_integration_installations?)
    suggestions = filter_write_actors(autocompleteQuery.suggestions)

    respond_to do |format|
      format.html_fragment do
        render partial: "branch_authorization/suggestions", formats: :html, locals: { suggestions: suggestions }
      end
      format.html do
        render partial: "branch_authorization/suggestions", locals: { suggestions: suggestions }
      end
    end
  end

  private

  def include_integration_installations?
    %w[push bypass_fp bypass_pr dismiss].include?(params[:type])
  end

  def check_permissions
    render_404 unless current_repository.async_can_edit_repo_protections?(current_user).sync
  end

  def filter_write_actors(actors)
    actors.select do |actor|
      if actor.instance_of?(Team)
        (actor.id_and_ancestor_ids & team_ids_with_write_access).any?
      elsif actor.instance_of?(User)
        # User owned repositories won't include the owner in the list of users, so explicitly check for that
        (user_ids_with_write_access.include? actor.id) ||
        (!current_repository.owner.organization? && (actor.id == current_repository.owner_id))
      elsif actor.instance_of?(IntegrationInstallation)
        integration_installation_ids_with_write_access.include? actor.id
      end
    end
  end

  memoize def team_ids_with_write_access
    current_repository.actor_ids(type: Team, min_action: :write)
  end

  memoize def user_ids_with_write_access
    current_repository.actor_ids(type: User, min_action: :write)
  end

  memoize def integration_installation_ids_with_write_access
    begin
      Authorization.service.actor_ids_with_granular_permissions_on(
        actor_type: IntegrationInstallation,
        subject_type: Repository,
        subject_ids: [current_repository.id],
        owner_ids: [current_repository.owner_id],
        permissions: [:contents, :single_file],
        min_action: :write,
      )
    end
  end
end
