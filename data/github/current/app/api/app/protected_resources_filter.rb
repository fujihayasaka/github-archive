# typed: false
# frozen_string_literal: true

module Api::App::ProtectedResourcesFilter
  def filter_protected_resources(type:, resources:, protected_account_ids:)
    if logged_in?
      case type
      when :starred
        repo_ids = resources.map(&:starrable_id)
        repos = if FeatureFlag.vexi.enabled?(:repos_by_id_api, default: false)
          ::Repositories.domain.by_ids(repo_ids)
        else
          Repository.find(repo_ids)
        end

        resources.to_a.delete_if do |star|
          protected_account_ids.include?(
            repos.detect { |repo| repo.id == star.starrable_id }.organization_id
          ) ||
          protected_account_ids.include?(
            repos.detect { |repo| repo.id == star.starrable_id }.owner_id
          )
        end
      when :watched
        resources.delete_if do |watched|
          protected_account_ids.include?(watched.organization_id) ||
          protected_account_ids.include?(watched.owner_id)
        end
      end
    end
  end
end
