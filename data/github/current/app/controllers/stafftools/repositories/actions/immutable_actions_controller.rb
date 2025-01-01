# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::ImmutableActionsController < StafftoolsController
  include RegistryTwo::PackagesMigrationHelper

  before_action :ensure_repo_exists
  before_action :ensure_ff_enabled_and_not_enterprise

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:index]

  def index
    immutable_actions_migration_enabled = current_repository.feature_enabled?(:migrate_to_immutable_actions) || current_repository.owner.feature_enabled?(:migrate_to_immutable_actions)
    rms_publish_enabled = current_repository.feature_enabled?(:rms_publish_immutable_actions) || current_repository.owner.feature_enabled?(:rms_publish_immutable_actions)

    raw_migration_status = get_migration_status_value(current_repository)
    if raw_migration_status.nil?
      migration_status = "not_started"
    else
      migration_status = raw_migration_status # completed or in_progress
    end

    render "stafftools/repositories/actions/immutable_actions",
      locals: {
        current_repository: current_repository,
        immutable_actions_migration_enabled: immutable_actions_migration_enabled,
        rms_publish_enabled: rms_publish_enabled,
        migration_status: migration_status
      }
  end

  def reset_migration # rubocop:todo GitHub/UseRestfulActions
    raw_migration_status = get_migration_status_value(current_repository)

    if raw_migration_status.nil?
      flash[:notice] = "Immutable actions migration is already in a not_started state"
    else
      flash[:notice] = "Resetting immutable actions migration status to not_started"
      delete_migration_status_key(current_repository)
    end

    redirect_to immutable_actions_stafftools_repository_path
  end

  private

  def ensure_ff_enabled_and_not_enterprise
    return render_404 unless current_repository.feature_enabled?(:immutable_actions_stafftools)
    render_404 if GitHub.enterprise?
  end
end
