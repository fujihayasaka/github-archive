# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeamMigrationsController < Stafftools::Businesses::BusinessBaseController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Stafftools::Businesses::EnterpriseTeamMigrationsController#create",
    "Stafftools::Businesses::EnterpriseTeamMigrationsController#update",
    "Stafftools::Businesses::EnterpriseTeamMigrationsController#destroy",
  ], T::Array[String])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Accounts,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:show, :create, :update, :destroy]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:update, :destroy],
    optional: true

  depends_on_clusters ApplicationRecord::Notify,
    only: [:destroy],
    optional: true

  before_action :ensure_feature_flag_enabled
  before_action :ensure_enterprise_teams_enabled

  sig { void }
  def show
    migrating_teams = find_migrations
    migrating_team_ids = migrating_teams.pluck(:enterprise_team_id)

    unmigrated_teams = EnterpriseTeam
      .owned_by(this_business)
      .where.not(id: migrating_team_ids)
      .order(:name)
      .paginate(page: current_page(:teams_page), per_page: DEFAULT_PAGE_SIZE)

    render "stafftools/businesses/enterprise_team_migrations/show", locals: {
      this_business: this_business,
      migrations: migrating_teams.paginate(page: current_page(:migrations_page), per_page: DEFAULT_PAGE_SIZE),
      unmigrated_teams: unmigrated_teams,
    }
  end

  sig { void }
  def create
    EnterpriseTeamMigrationStartJob.perform_later(business: this_business)

    flash[:notice] = "Migration has been enqueued for all Enterprise teams. Refresh to see progress."
    redirect_to stafftools_enterprise_team_migration_path(this_business)
  end

  sig { void }
  def update
    migrations = find_migrations.where(migration_status: :dual_write)

    unless migrations.exists?
      flash[:error] = "No migrations are ready to complete."
      return redirect_to stafftools_enterprise_team_migration_path(this_business)
    end

    EnterpriseTeamMigrationCompleteJob.perform_later(business: this_business)
    flash[:notice] = "Completion has been enqueued for all ready migrations. Refresh to see progress."
    redirect_to stafftools_enterprise_team_migration_path(this_business)
  end

  sig { void }
  def destroy
    migrations = find_migrations.where.not(migration_status: :completed)

    unless migrations.exists?
      flash[:error] = "No migrations to reset."
      return redirect_to stafftools_enterprise_team_migration_path(this_business)
    end

    EnterpriseTeamMigrationResetJob.perform_later(business: this_business)
    flash[:notice] = "Reset has been enqueued for all in-progress migrations. Refresh to see progress."
    redirect_to stafftools_enterprise_team_migration_path(this_business)
  end

  private

  sig { returns(ActiveRecord::Relation) }
  def find_migrations
    enterprise_team_ids = EnterpriseTeam.unscoped.owned_by(this_business).pluck(:id)
    EnterpriseTeamMigration
      .where(enterprise_team_id: enterprise_team_ids)
      .preload(:enterprise_team, :business_team)
      .order(:created_at)
  end

  sig { void }
  def ensure_feature_flag_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:enterprise_teams_v2_stafftools_migration, current_user, default: false)
  end

  sig { void }
  def ensure_enterprise_teams_enabled
    render_404 unless this_business.enterprise_teams_enabled?
  end
end
