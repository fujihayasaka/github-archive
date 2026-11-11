# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class RepositoryByNwo
      def self.async_repo_and_owner(name_with_owner, follow_repo_redirect)
        repo_promise = Platform::Loaders::RepositoryByNwo.load(name_with_owner).then do |repo|
          next repo if repo
          Platform::Loaders::RedirectedRepositoryByNwo.load(name_with_owner) if follow_repo_redirect
        end

        repo_promise.then do |repo|
          next [nil, nil] if repo.nil?
          repo.async_owner.then { |owner| [repo, owner] }
        end
      end

      def self.async_repository_with_owner(permission:, viewer:, login:, name:, follow_repo_redirect: true)
        name_with_owner = "#{login}/#{name}"
        repo_promise = async_repo_and_owner(name_with_owner, follow_repo_redirect).then do |repo, owner|
          next if repo.blank? || owner.blank?

          permission.typed_can_see?("User", owner).then do |owner_readable|
            next unless owner_readable || owner.hide_from_user?(viewer) ## TODO: experiment later to see if we can just rely on ability to see repo

            permission.typed_can_see?("Repository", repo).then do |repo_readable|
              next unless repo_readable

              Platform::Security::RepositoryAccess.async_permit_with_message(repo).then do |(has_permission, _message)|
                next unless has_permission

                if owner.is_a?(::Organization)
                  current_org = owner
                end

                permission.access_allowed?(:v4_get_repo, repo: repo, current_org: current_org, resource: repo, from_invitation: false, allow_integrations: true, allow_user_via_granular_actor: true).then do |can_get_repo|
                  repo if can_get_repo
                end
              end
            end
          end
        end
        repo_promise.then do |repo|
          repo || raise(Errors::NotFound, "Could not resolve to a Repository with the name '#{login}/#{name}'.")
        end
      end
    end
  end
end
