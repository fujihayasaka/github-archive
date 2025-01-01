# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-classroom_repositories"

module Api::Internal::Twirp::Classroom
  module ClassroomRepositories
    module V1

      # Handler for the MonolithTwirp::Classroom::ClassroomRepositories::V1::ClassroomRepositoriesAPIService
      class ClassroomRepositoriesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::ClassroomRepositories::V1::ClassroomRepositoriesAPIService
        connected_to_writing_for :create_classroom_repository_records, :create_repository,
          :create_update_classroom_repository_records, :create_cloned_repository

        class CreateRepositoryParams
          include ActiveModel::Model
          attr_accessor :admins,
            :assignment_id,
            :assignment_name,
            :assignment_type,
            :classroom_id,
            :classroom_name,
            :deadline,
            :has_autograding,
            :installation_id,
            :is_private,
            :org_id,
            :repo_name,
            :starter_code_repository_id,
            :team_id,
            :user_id

          validates :repo_name, presence: true
          validates :is_private, presence: true

          validates :installation_id, numericality: { greater_than: 0 }
          validates :id_for_team, numericality: { greater_than: 0, allow_nil: true }
          validates :id_for_user, numericality: { greater_than: 0, allow_nil: true }

          def renderable_error
            errors.full_messages.join(", ")
          end

          def id_for_team
            @team_id  == 0 ?  nil : @team_id
          end

          def id_for_user
            @user_id  == 0 ?  nil : @user_id
          end
        end

        # Public: Implementation of the CreateClonedRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::ClassroomRepositories::V1::CreateClonedRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::ClassroomRepositories::V1::CreateClonedRepositoryResponse, or a Twirp::Error.
        def create_cloned_repository(req, env)
          params = CreateRepositoryParams.new(req.to_h)
          return Twirp::Error.invalid_argument(params.renderable_error) unless params.valid?

          access_check = ClassroomGitHubApp::RepositoryWriteAccessCheck.new(starter_code_repository_id: params.starter_code_repository_id, installation_id: params.installation_id)
          return Twirp::Error.permission_denied(access_check.renderable_error) unless access_check.valid?

          student = User.find_by(id: params.id_for_user)
          team = Team.find_by(id: params.id_for_team)

          classroom_repo = ClassroomRepository.new(
            classroom_id: params.classroom_id,
            assignment_id: params.assignment_id,
            user: student,
            team: team
          )

          begin
            starter_repo = params.starter_code_repository_id ? access_check.starter_repo : nil
            ClassroomRepository::RepositoryBuilder.perform(
              classroom_repo,
              access_check.installation.bot,
              access_check.org,
              params.repo_name,
              params.is_private,
              starter_repo
            )
            classroom_repo.save!
          rescue ActiveRecord::RecordInvalid, ClassroomRepository::RepositoryBuilder::FailedRepositoryCreationError => e
            return { created: false, reason: e.message }
          end

          repo = classroom_repo.repository
          if repo.nil?
            return { created: false, reason: "Repository not found" }
          end
          if repo.actions_app_installed?
            result = repo.enable_actions_app(actor: student, entry_point: :twirp_api_classroom_repositories_create_clone_api_handler)
            unless result.success?
              reason = result.reason || ""
              return { id: repo.id, created: true, reason: "Actions cannot be enabled. Reason: #{reason}" }
            end
          end

          { id: repo.id, created: true, reason: "" }
        end

        # Public: Implementation of the CreateUpdateClassroomRepositoryRecords Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::ClassroomRepositories::V1::CreateClassroomRepositoryRecordsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::ClassroomRepositories::V1::CreateUpdateClassroomRepositoryRecordsResponse, or a Twirp::Error.
        def create_update_classroom_repository_records(req, env)
          team_id = req.team_id == 0 ? nil : req.team_id
          user_id = req.user_id == 0 ? nil : req.user_id
          repo_id = req.id

          existing_repo = Repository.find_by(id: repo_id)
          if existing_repo
            begin
              classroom_repo = ClassroomRepository.retry_on_find_or_create_error do
                ClassroomRepository.find_by(repository_id: repo_id) || ClassroomRepository.new(repository_id: repo_id)
              end
              classroom_repo.update!(
                classroom_id: req.classroom_id,
                assignment_id: req.assignment_id,
                team_id: team_id,
                user_id: user_id
              )
            rescue ActiveRecord::RecordInvalid => e
              { id: existing_repo.id, created: false, reason: e.message }
            else
              { id: existing_repo.id, created: true, reason: "" }
            end
          else
            { id: repo_id, created: false, reason: "Assignment Repository not found" }
          end
        end
      end
    end
  end
end
