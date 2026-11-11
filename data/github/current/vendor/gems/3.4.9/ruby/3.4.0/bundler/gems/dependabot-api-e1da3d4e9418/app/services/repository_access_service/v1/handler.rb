# frozen_string_literal: true

module RepositoryAccessService
  module V1
    class Handler
      def get_repository_access(req, _env)
        account = Account.find_by(github_id: req.owner_github_id)
        unless account
          return DependabotApi::V1::GetRepositoryAccessResponse.new(
            access_editable: false
          )
        end

        repo_accesses = account.repository_accesses

        DependabotApi::V1::GetRepositoryAccessResponse.new(
          access_editable: true,
          repository_github_ids: repo_accesses.pluck(:github_id),
        )
      end

      def set_selected_repositories(req, _env)
        account = Account.find_by(github_id: req.owner_github_id)
        return Twirp::Error.not_found("owner_github_id not found") unless account

        sync_repository_access(req, account)
        {}
      end

      private

      def sync_repository_access(req, account)
        RepositoryAccess.transaction do
          existing = account.repository_accesses

          # Add any github_ids that are not found:
          if req.repository_github_ids.any?
            RepositoryAccess.insert_all(
              req.repository_github_ids.map do |github_id|
                {
                  account_id: account.id,
                  github_id: github_id,
                  created_at: Time.zone.now,
                }
              end
            )
          end

          # Remove any github_ids that are no longer included:
          existing.where.not(github_id: req.repository_github_ids.to_a).
            delete_all
        end
      end
    end
  end
end
