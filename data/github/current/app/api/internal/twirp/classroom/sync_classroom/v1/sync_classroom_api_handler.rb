# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-sync_classroom"

module Api::Internal::Twirp::Classroom
  module SyncClassroom
    module V1
      # Handler for the MonolithTwirp::Classroom::SyncClassroom::V1::SyncClassroomAPIService
      class SyncClassroomAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::SyncClassroom::V1::SyncClassroomAPIService
        connected_to_writing_for :create_classroom_assignment_records, :create_classroom_classroom_records,
          :create_classroom_user, :create_classroom_instructor_record, :delete_classroom_assignment_records,
          :delete_classroom_classroom_records, :delete_classroom_instructor_record

        # Public: Implementation of the CreateClassroomAssignmentRecords Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::SyncClassroom::V1::CreateClassroomAssignmentRecordsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::SyncClassroom::V1::CreateClassroomAssignmentRecordsResponse, or a Twirp::Error.
        def create_classroom_assignment_records(req, env)
          begin
            classroom_assignment = ClassroomAssignment.retry_on_find_or_create_error do
              ClassroomAssignment.find_by(id: req.id) || ClassroomAssignment.new(id: req.id)
            end

            classroom_assignment.update!(
              name: req.assignment_name,
              assignment_type: req.assignment_type,
              starter_code_repository_id: req.starter_code_repository_id == 0 ? nil : req.starter_code_repository_id,
              classroom_classroom_id: req.classroom_id == 0 ? nil : req.classroom_id,
              has_autograding: req.has_autograding,
              deadline: req.deadline
            )
          rescue ActiveRecord::RecordInvalid => e
            { id: req.id, created: false, reason: e.message }
          else
            { id: classroom_assignment.id, created: true, reason: "" }
          end
        end

        # Public: Implementation of the DeleteClassroomAssignmentRecords Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::SyncClassroom::V1::DeleteClassroomAssignmentRecordsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::SyncClassroom::V1::DeleteClassroomAssignmentRecordsResponse, or a Twirp::Error.
        def delete_classroom_assignment_records(req, env)
          assignment = ClassroomAssignment.find(req.id)
          assignment.destroy!
          { deleted: true }
        rescue ActiveRecord::RecordNotFound
          { deleted: true }
        end

        # Public: Implementation of the CreateClassroomClassroomRecords Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::SyncClassroom::V1::CreateClassroomClassroomRecordsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::SyncClassroom::V1::CreateClassroomClassroomRecordsResponse, or a Twirp::Error.
        def create_classroom_classroom_records(req, env)
          begin
            classroom_classroom = ClassroomClassroom.retry_on_find_or_create_error do
              ClassroomClassroom.find_by(id: req.id) || ClassroomClassroom.new(id: req.id)
            end

            classroom_classroom.update!(
              name: req.classroom_name
            )
          rescue ActiveRecord::RecordInvalid => e
            { id: req.id, created: false, reason: e.message }
          else
            { id: classroom_classroom.id, created: true, reason: "" }
          end
        end

        # Public: Implementation of the DeleteClassroomClassroomRecords Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::SyncClassroom::V1::DeleteClassroomClassroomRecordsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::SyncClassroom::V1::DeleteClassroomClassroomRecordsResponse, or a Twirp::Error.
        def delete_classroom_classroom_records(req, env)
          classroom = ClassroomClassroom.find(req.id)
          classroom.destroy!
          { deleted: true }
        rescue ActiveRecord::RecordNotFound
          { deleted: true }
        end

        # Public: Implementation of the CreateClassroomUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::SyncClassroom::V1::CreateClassroomUser.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::SyncClassroom::V1::CreateClassroomUserResponse, or a Twirp::Error.
        def create_classroom_user(req, env)
          user_id = id_argument(req.user_id)
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user not found", argument: "user_id") unless user

          begin
            ClassroomUser.retry_on_find_or_create_error do
              ClassroomUser.find_by(user: user) || ClassroomUser.create!(user: user)
            end
          rescue ActiveRecord::RecordInvalid => e
            { created: false, reason: e.message }
          else
            { created: true, reason: "" }
          end
        end

        # Public: Implementation of the CreateClassroomInstructorRecord Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::SyncClassroom::V1::CreateClassroomInstructorRecordRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::SyncClassroom::V1::CreateClassroomInstructorRecordResponse, or a Twirp::Error.
        def create_classroom_instructor_record(req, env)
          user_id = id_argument(req.user_id)
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user not found", argument: "user_id") unless user

          classroom_user = ClassroomUser.find_by(user: user)
          return Twirp::Error.not_found("classroom user not found", argument: "user_id") unless classroom_user

          classroom_id = id_argument(req.classroom_id)
          unless classroom_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "classroom_id")
          end

          classroom = ClassroomClassroom.find_by(id: classroom_id)
          return Twirp::Error.not_found("classroom not found", argument: "classroom_id") unless classroom

          begin
            classroom_instructor = ClassroomInstructor.retry_on_find_or_create_error do
              ClassroomInstructor.find_by(classroom_classroom_id: classroom.id, classroom_user_id: classroom_user.id) || ClassroomInstructor.create!(classroom_classroom_id: classroom.id, classroom_user_id: classroom_user.id)
            end
          rescue ActiveRecord::RecordInvalid => e
            { id: classroom_instructor.id, created: false, reason: e.message }
          else
            { id: classroom_instructor.id, created: true, reason: "" }
          end
        end

        # Public: Implementation of the DeleteClassroomInstructorRecord Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::SyncClassroom::V1::DeleteClassroomInstructorRecordRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::SyncClassroom::V1::DeleteClassroomInstructorRecordResponse, or a Twirp::Error.
        def delete_classroom_instructor_record(req, env)
          classroom_user_id = ClassroomUser.find_by(user_id: req.id)&.id
          classroom_instructor = ClassroomInstructor.find_by!(classroom_classroom_id: req.classroom_id, classroom_user_id: classroom_user_id)
          classroom_instructor.destroy!
          { deleted: true }
        rescue ActiveRecord::RecordNotFound
          { deleted: true }
        end
      end
    end
  end
end
