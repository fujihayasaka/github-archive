# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-assignment_reuse"

module Api::Internal::Twirp::Classroom
  module AssignmentReuse
    module V1
      # Handler for the MonolithTwirp::Classroom::AssignmentReuse::V1::AssignmentReuseAPIService
      class AssignmentReuseAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::AssignmentReuse::V1::AssignmentReuseAPIService
        connected_to_writing_for :copy_starter_code_repository_to_org

        # Public: Implementation of the CopyStarterCodeRepositoryToOrg Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::AssignmentReuse::V1::CopyStarterCodeRepositoryToOrgRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::AssignmentReuse::V1::CopyStarterCodeRepositoryToOrgResponse, or a Twirp::Error.
        def copy_starter_code_repository_to_org(req, env)
          begin
            unless id_argument(req.organization_id)
              return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
            end

            unless id_argument(req.actor_id)
              return Twirp::Error.invalid_argument("must be non-empty", argument: "actor_id")
            end

            unless id_argument(req.source_repo_id)
              return Twirp::Error.invalid_argument("must be non-empty", argument: "source_repo_id")
            end

            unless id_argument(req.assignment_id)
              return Twirp::Error.invalid_argument("must be non-empty", argument: "assignment_id")
            end

            classroom_assignment = ClassroomAssignment.find(req.assignment_id)
            target_organization = User.find(req.organization_id)
            actor = User.find(req.actor_id)
            source_repo = ::Repositories::Public.find_active!(req.source_repo_id)

            unless source_repo.readable_by?(actor) && target_organization.writable_by?(actor)
              return Twirp::Error.permission_denied("User does not have necessary permissions", argument: "actor_id")
            end

            Repository.transaction do
              starter_code_repo = ClassroomAssignment::RepositoryBuilder.perform(classroom_assignment, source_repo, actor, target_organization)
              starter_code_repo.save!

              Repository::Clone.from_repo(source_repo: source_repo, destination_repo: starter_code_repo)

              starter_code_repo.analyze_languages

              { starter_code_repo_id: starter_code_repo.id, created: true, reason: "" }
            end
          rescue ActiveRecord::RecordNotFound => e
            { starter_code_repo_id: 0, created: false, reason: e.message }
          rescue ClassroomAssignment::RepositoryBuilder::FailedRepositoryCreationError => e
            { starter_code_repo_id: 0, created: false, reason: e.message }
          rescue ActiveRecord::Rollback => e
            { starter_code_repo_id: 0, created: false, reason: e.message }
          end
        end
      end
    end
  end
end
