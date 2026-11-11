# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::AccessToAlertsController < AbstractRepositoryController
  include SecurityAnalysisSettingsHelper

  skip_before_action :privacy_check, only: [:update_alerts]

  before_action :ensure_can_access_vulnerabilities, only: [:update_alerts]
  before_action :manage_security_products_permission_required, only: [:update_alerts, :authorized_actor, :suggestions]
  before_action :sudo_filter, only: [:update_alerts]
  before_action :login_required, only: [:authorized_actor, :suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
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
    ApplicationRecord::Iam,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:authorized_actor, :suggestions], optional: true

  VALID_ACTOR_TYPES = %w[user team].freeze

  def update_alerts # rubocop:todo GitHub/UseRestfulActions
    Repository.transaction do
      current_repository.vulnerability_manager.replace_vulnerability_alert_restricted_users_and_teams(
       user_ids: Array(params[:vulnerability_user_ids]),
       team_ids: Array(params[:vulnerability_team_ids]),
     )
      current_repository.save!
    end

    flash[:notice] = "Alert options saved"
    redirect_to :back
  end

  def authorized_actor # rubocop:todo GitHub/UseRestfulActions
    actor_type, actor_id = params[:item]&.split("/", 2)
    return head 404 unless VALID_ACTOR_TYPES.include?(actor_type)

    actor =
      case actor_type
      when "user"
        User.find_by(id: actor_id)
      when "team"
        Team.find_by(id: actor_id)
      end

    return head 404 if filter_read_actors([actor]).first.nil?

    respond_to do |format|
      format.html do
        render partial: "branch_authorization/authorized_actor", locals: {
          actor: actor,
          form_field_name: "vulnerability",
        }
      end
    end
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    autocomplete_query = AutocompleteQuery.new(current_user, params[:q],
      organization: current_repository.organization,
      include_teams: true, repository: current_repository,
      include_integration_installations: false)
    suggestions = filter_read_actors(autocomplete_query.suggestions)

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

  def filter_read_actors(actors)
    actors.select do |actor|
      if actor.instance_of?(Team)
        (actor.id_and_ancestor_ids & team_ids_with_read_access).any?
      elsif actor.instance_of?(User)
        user_ids_with_read_access.include? actor.id
      end
    end
  end

  def team_ids_with_read_access # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @team_ids_with_read_access ||= current_repository.actor_ids(type: Team, min_action: :read)
  end

  def user_ids_with_read_access # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @user_ids_with_read_access ||= current_repository.actor_ids(type: User, min_action: :read)
  end

  def ensure_can_access_vulnerabilities
    token_scanning = SecretScanning::Features::Repo::TokenScanning.new(current_repository)
    if !((current_repository.vulnerability_alerts_enabled? || token_scanning.enabled?) && current_repository.owner.is_a?(Organization))
      render_404
    end
  end
end
