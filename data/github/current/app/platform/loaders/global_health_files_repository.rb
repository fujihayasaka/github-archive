# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class GlobalHealthFilesRepository < Platform::Loader
      def self.load(owner_id)
        self.for.load(owner_id)
      end

      def fetch(owner_ids)
        if GitHub.flipper[:global_health_files_repository_loader_new_fetch_implementation].enabled?
          repos = fetch_repos(owner_ids)
        else
          repos = fetch_repos_without_emus(owner_ids)
        end
        repos.index_by(&:owner_id)
      end

      def fetch_repos(owner_ids)
        repos = ::Repository.owned_by(owner_ids).with_global_health_files_name.active.to_a
        Promise.all(repos.map(&:async_business)).then do
          repos.filter do |repo|
            # If the repo is enterprise managed allow the health files repo to be internal
            # since public repos can't be created in those scenarios.
            owner = repo.owner
            if GitHub.flipper[:allow_internal_org_config_repo_if_public_repos_disabled].enabled?(owner)
              is_enterprise_managed = owner.is_a?(Organization) ? owner.enterprise_managed_user_enabled? : owner&.is_enterprise_managed?
              if is_enterprise_managed
                repo.internal? || repo.public?
              else
                repo.public?
              end
            else
              repo.public?
            end
          end
        end.sync
      end

      def fetch_repos_without_emus(owner_ids)
        ::Repository.owned_by(owner_ids).with_global_health_files_name.active.public_scope
      end
    end
  end
end
