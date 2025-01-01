# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetAccountDetailsForRepository
        REPO_NOT_FOUND_MESSAGE = "repository not found for the given repository_id"

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @repository_id = request.repository_id&.global_id
        end

        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if @repository_id.nil?

          log_fields = {
            fn: "GetAccountDetailsForRepository#call",
            request_id: GitHub.context[:request_id],
            catalog_service: "github/c2c-actions-experience",
          }

          begin
            decoded_id = Platform::Helpers::NodeIdentification.from_global_id(@repository_id)
          rescue Platform::Errors::NotFound
            GitHub::Logger.log(log_fields.merge({ msg: "unresolvable repository_id encountered" }))
            return Twirp::Error.not_found("unresolvable repository global id")
          end

          return Twirp::Error.invalid_argument("must be the globalID of a repository", argument: "repository_id") unless decoded_id.first == "Repository"

          repo = Repositories.domain.by_id(decoded_id.last)

          unless repo
            GitHub::Logger.log(log_fields.merge({ msg: REPO_NOT_FOUND_MESSAGE }))
            return Twirp::Error.not_found(REPO_NOT_FOUND_MESSAGE)
          end

          owner = repo.owner
          {
            account_type: owner_account_type(owner),
            plan_name: owner_plan(owner),
          }
        end

        private

        def owner_account_type(owner)
          if owner.is_a?(Organization)
            MonolithTwirp::Actions::Core::V1::RepositoryOwner::REPOSITORY_OWNER_ORGANIZATION
          elsif owner.is_a?(User)
            MonolithTwirp::Actions::Core::V1::RepositoryOwner::REPOSITORY_OWNER_USER
          else
            MonolithTwirp::Actions::Core::V1::RepositoryOwner::REPOSITORY_OWNER_INVALID
          end
        end

        def owner_plan(owner)
          plan = owner.plan
          if plan.free_with_addons?
            MonolithTwirp::Actions::Core::V1::PlanName::PLAN_NAME_FREE_WITH_ADD_ONS
          elsif plan.business?
            MonolithTwirp::Actions::Core::V1::PlanName::PLAN_NAME_BUSINESS
          elsif plan.business_plus?
            MonolithTwirp::Actions::Core::V1::PlanName::PLAN_NAME_BUSINESS_PLUS
          elsif plan.pro?
            MonolithTwirp::Actions::Core::V1::PlanName::PLAN_NAME_PRO
          elsif plan.free?
            MonolithTwirp::Actions::Core::V1::PlanName::PLAN_NAME_FREE
          else
            MonolithTwirp::Actions::Core::V1::PlanName::PLAN_NAME_OTHER
          end
        end
      end
    end
  end
end
