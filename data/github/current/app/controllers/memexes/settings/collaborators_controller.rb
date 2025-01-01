# typed: true
# frozen_string_literal: true

class Memexes::Settings::CollaboratorsController < Memexes::Controller

  include MemexesHelper
  include BaseHelpers::Helpers
  include ApplicationController::VerifiedFetchDependency
  include Instrumentation::Model

  before_action :login_required
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_admin_access
  before_action :require_permission, only: [:update]
  before_action :load_actors_from_params, only: [:update, :destroy]

  allow_verified_fetch

  # Cluster dependencies analysis will be enabled for these non-get requests:
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::Settings::CollaboratorsController#update",
    "Memexes::Settings::CollaboratorsController#destroy",
  ].freeze

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    headers["Cache-Control"] = "no-cache, no-store"
    render(json: { collaborators: this_memex.collaborators(current_user) })
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:update]

  depends_on_clusters ApplicationRecord::Iam,
    only: [:update],
    optional: true

  def update
    role_to_grant = params.require(:permission)

    unless Role::MEMEX_PROJECTS_SYSTEM_ROLES.include?(role_to_grant)
      flash[:error] = "Can't grant permissions"
      return head :bad_request
    end

    existing_collaborators = this_memex.collaborators(current_user)
    collaborators = []

    # Grant the new roles for all the valid actor_ids
    new_role = T.must(Role.internal_role_by_name(role_to_grant))
    other_memex_roles = Role.system_project_roles.where.not(id: new_role.id)

    actors.each do |actor|
      existing_collab = existing_collaborators.find do |existing|
        hash = existing.to_hash
        hash[:id] == actor.id && hash[:actor_type] == actor.class.to_s.downcase
      end

      old_role_name = existing_collab&.role&.name

      other_memex_roles.each do |role|
        this_memex.revoke_role(actor, role)
      end

      begin
        retry_on_find_or_create_error do
          this_memex.grant_role(actor, new_role)
        end

        collaborators.push MemexProjectCollaborator.new(actor, new_role)
        instrument_collaborator(actor, existing_collab ? :update : :add, new_role.name, old_role_name)
      rescue ArgumentError, Permissions::Granters::RoleGranter::GrantFailure
        @failed.push actor_identifier(actor)
      end
    end

    render(json: { collaborators: collaborators, failed: @failed })
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:destroy]

  depends_on_clusters ApplicationRecord::Iam,
    only: [:destroy],
    optional: true

  def destroy
    failed = this_memex.remove_collaborators(actors)
    @failed.push(*failed)

    removed = actors.select { |actor| !failed.include?("#{actor.class.to_s.downcase}/#{actor.id}") }
    removed.map { |actor| instrument_collaborator(actor, :remove) }
    render(json: { failed: @failed })
  end

  private

  attr_reader :actors

  def instrument_collaborator(collaborator, action, project_role = nil, old_project_role = nil) # rubocop:todo GitHub/UseRestfulActions
    collaborator_type = "external user"

    if memex_owner.organization?
      if collaborator.is_a?(Team)
        collaborator_type = "team"
      elsif memex_owner.member?(collaborator)
        collaborator_type = "member"
      elsif memex_owner.user_is_outside_collaborator?(collaborator.id)
        collaborator_type = "outside collaborator"
      end
    end

    instrument action, { collaborator_type:, collaborator:, project_role:, old_project_role: }
    GlobalInstrumenter.instrument "memex_event", {
      actor: current_user,
      memex_project: this_memex,
      name: "settings_collaborator_#{action}",
      context: {
        collaborator_type: "#{collaborator_type}",
        collaborator_id: "#{collaborator.id}"
      }.to_json
    }
  end

  # Default action prefix for audit log events
  sig { returns(String) }
  def event_prefix
    "project_collaborator"
  end

  # Default payload values for audit log events
  sig { returns(Hash) }
  def event_payload
    owner = this_memex.owner

    {
      actor: current_user,
      project: this_memex,
      project_number: this_memex&.number,
      public_project: this_memex&.public?,
      project_name: this_memex&.name,
    }.tap { _1[owner.event_prefix] = owner }.compact
  end

  def require_permission
    head :bad_request unless params[:permission]
  end

  # @param collaborators: an array of strings of shape [ 'user/user1_id',  'team/team1_id', 'user/user2_id' ]
  def load_actors_from_params
    @actors = []
    @failed = []

    return head :bad_request unless params[:collaborators]

    collaborator_params = params.require(:collaborators)

    # When we get collaborators from a query string, convert it to json otherwise it's already json
    # This is a legacy behavior that should be removed https://github.com/github/memex/issues/11236
    parsed_collaborators = if collaborator_params.is_a?(String)
      GitHub::JSON.parse(collaborator_params)
    else
      collaborator_params
    end

    parsed_collaborators.each do |actor|
      # Available types are `user` and `team`
      # Examples: `user/123`, `team/321`
      parts = actor.split("/", 2)

      unless UserRole::VALID_ACTOR_TYPES.include? parts[0].capitalize
        @failed.push actor
        next
      end

      valid_actor = load_actor(parts[0], parts[1])
      if valid_actor
        @actors.push valid_actor
      else
        @failed.push actor
      end
    end
  end

  def load_actor(actor_type, actor_id)
    actor = if actor_type == "user"
      User.includes(:profile).find_by(id: actor_id)
    elsif actor_type == "team"
      Team.where(organization: this_memex.owner).find_by(id: actor_id)
    end
    actor if valid_actor?(actor)
  end

  def actor_identifier(actor)
    actor_type = actor.class.to_s.downcase
    "#{actor_type}/#{actor.id}"
  end

  # Private: Determine if the Team or User is permitted to be added or removed from a project.
  #
  # actor - The Team or User to check
  #
  # Returns true if a valid actor, or false otherwise.
  def valid_actor?(actor)
    # If the actor is a user and the action is destroy, we can skip the permission check
    return true if action_name == "destroy" && actor&.is_a?(User)

    return false unless actor&.respond_to?(:can_be_added_to_memex_project?)
    actor.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: current_user)
  end
end
