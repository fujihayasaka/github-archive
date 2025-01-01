# typed: true
# frozen_string_literal: true

class Actions::ImmutableActionsController < AbstractRepositoryController
  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :ensure_packages_write_permission
  before_action :require_actions_enabled
  before_action :migration_enabled

  allow_verified_fetch only: [:migrate]

  def migrate # rubocop:todo GitHub/UseRestfulActions
    MigrateSemverReleasesToImmutableActionsJob.perform_later(current_repository, current_user)
    release_tags = current_repository.releases.pluck(:tag_name).uniq
    @semver_parser = Actions::Resolver::V2::Internal::SemverParser.new
    semver_tags = release_tags.select { |tag| @semver_parser.is_full_semver?(tag) }
    skipped_tags = release_tags - semver_tags

    respond_to do |format|
      format.json do
        render json: {
          "tags_skipped": skipped_tags,
          "tags_to_be_migrated": semver_tags,
        }
      end
    end
  end

  private

  def migration_enabled
    render_404 unless current_repository.feature_enabled?(:migrate_to_immutable_actions) || current_repository.owner.feature_enabled?(:migrate_to_immutable_actions)
  end

  def require_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def ensure_packages_write_permission
    render_404 unless current_repository.resources.packages.writable_by?(current_user)
  end
end
