# typed: true
# frozen_string_literal: true

require "monolith-twirp-classroom-classroom_codespaces"

module Api::Internal::Twirp::Classroom
  module ClassroomCodespaces
    module V1
      # Handler for the MonolithTwirp::Classroom::ClassroomCodespaces::V1::ClassroomCodespacesAPIService
      class ClassroomCodespacesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["classroom"]
        handles_service MonolithTwirp::Classroom::ClassroomCodespaces::V1::ClassroomCodespacesAPIService
        connected_to_writing_for :enable_classroom_codespaces_for_organization, :disable_classroom_codespaces, :revoke_classroom_codespaces_from_organization

        # Public: Implementation of the RevokeClassroomCodespacesFromOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::ClassroomCodespaces::V1::RevokeClassroomCodespacesFromOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::ClassroomCodespaces::V1::RevokeClassroomCodespacesFromOrganizationResponse, or a Twirp::Error.
        def revoke_classroom_codespaces_from_organization(req, env)
          unless id_argument(req.organization_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          unless id_argument(req.teacher_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "teacher_id")
          end

          unless target_organization = ClassroomOrganization.locate(organization_id: req.organization_id)
            return Twirp::Error.not_found("organization not found", argument: "organization_id")
          end

          unless teacher = ClassroomUser.find_by(user_id: req.teacher_id)
            return Twirp::Error.not_found("classroom user record not found", argument: "teacher_id")
          end

          is_revoked = target_organization.disable_classroom_codespaces(teacher)
          {
            organization_id: req.organization_id,
            teacher_id: req.teacher_id,
            is_revoked: is_revoked,
            reason: is_revoked ? nil : "An error occured while revoking classroom codespaces"
          }
        end

        # Public: Implementation of the DisableClassroomCodespaces Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::ClassroomCodespaces::V1::DisableClassroomCodespacesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::ClassroomCodespaces::V1::DisableClassroomCodespacesResponse, or a Twirp::Error.
        def disable_classroom_codespaces(req, env)
          unless id_argument(req.organization_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          unless id_argument(req.teacher_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "teacher_id")
          end

          unless target_organization = ClassroomOrganization.locate(organization_id: req.organization_id)
            return Twirp::Error.not_found("organization not found", argument: "organization_id")
          end

          unless teacher = ClassroomUser.find_by(user_id: req.teacher_id)
            return Twirp::Error.not_found("classroom user record not found", argument: "teacher_id")
          end

          unless teacher.verified_teacher?
            return Twirp::Error.permission_denied("teacher must be a verified teacher")
          end

          unless target_organization.adminable_by?(teacher)
            return Twirp::Error.permission_denied("teacher must be admin of this organization")
          end

          is_disabled = target_organization.disable_classroom_codespaces(teacher)
          {
            organization_id: req.organization_id,
            teacher_id: req.teacher_id,
            is_disabled: is_disabled,
            reason: is_disabled ? nil : "An error occured while disabling classroom codespaces"
          }
        end
        #
        # Public: Implementation of the EnableClassroomCodespacesForOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::ClassroomCodespaces::V1::EnableClassroomCodespacesForOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::ClassroomCodespaces::V1::EnableClassroomCodespacesForOrganizationResponse, or a Twirp::Error.

        def enable_classroom_codespaces_for_organization(req, env)
          unless id_argument(req.organization_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          unless id_argument(req.teacher_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "teacher_id")
          end

          unless target_organization = ClassroomOrganization.locate(organization_id: req.organization_id)
            return Twirp::Error.not_found("organization not found", argument: "organization_id")
          end

          unless teacher = ClassroomUser.find_by(user_id: req.teacher_id)
            return Twirp::Error.not_found("classroom user record not found", argument: "teacher_id")
          end

          unless teacher.verified_teacher?
            return Twirp::Error.permission_denied("teacher must be a verified teacher")
          end

          unless target_organization.meets_minimal_plan_for_classroom_codespaces?
            return Twirp::Error.permission_denied("organization must be on the team or enterprise plan")
          end

          unless target_organization.adminable_by?(teacher)
            return Twirp::Error.permission_denied("teacher must be admin of this organization")
          end

          target_organization.enable_classroom_codespaces(teacher)

          {
            organization_id: req.organization_id,
            teacher_id: req.teacher_id,
            is_enabled: true,
            reason: ""
          }
        end

        # Public: Implementation of the CheckClassroomCodespacesStatusForOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::ClassroomCodespaces::V1::CheckClassroomCodespacesStatusForOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::ClassroomCodespaces::V1::CheckClassroomCodespacesStatusForOrganizationResponse, or a Twirp::Error.
        def check_classroom_codespaces_status_for_organization(req, env)
          unless id_argument(req.organization_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          unless target_organization = ClassroomOrganization.locate(organization_id: req.organization_id)
            return Twirp::Error.not_found("organization not found", argument: "organization_id")
          end

          if target_organization.classroom_codespaces_enabled?
            {
              organization_id: req.organization_id,
              is_enabled: true,
              reason: ""
            }
          else
            status = target_organization.classroom_codespaces_setup_status

            {
              organization_id: req.organization_id,
              is_enabled: false,
              reason: status.to_json
            }
          end
        end

        # Public: Implementation of the CheckIfOrganizationEligibleForClassroomCodespaces Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::ClassroomCodespaces::V1::CheckIfOrganizationEligibleForClassroomCodespacesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::ClassroomCodespaces::V1::CheckIfOrganizationEligibleForClassroomCodespacesResponse, or a Twirp::Error.
        def check_if_organization_eligible_for_classroom_codespaces(req, env)
          unless id_argument(req.organization_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "organization_id")
          end

          unless target_organization = ClassroomOrganization.locate(organization_id: req.organization_id)
            return Twirp::Error.not_found("organization not found", argument: "organization_id")
          end

          if target_organization.meets_minimal_plan_for_classroom_codespaces?
            { organization_id: req.organization_id, is_eligible: true, reason: "" }
          else
            {
              organization_id: req.organization_id,
              is_eligible: false,
              reason: %Q[Organization Plan is "#{target_organization.plan}", should be "team" or "enterprise"]
            }
          end
        end

        # Public: Implementation of the CheckTeacherVerifiedStatus Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Classroom::ClassroomCodespaces::V1::CheckTeacherVerifiedStatusRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Classroom::ClassroomCodespaces::V1::CheckTeacherVerifiedStatusResponse, or a Twirp::Error.
        def check_teacher_verified_status(req, env)
          unless id_argument(req.teacher_id)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "teacher_id")
          end

          unless teacher = ClassroomUser.find_by(user_id: req.teacher_id)
            return Twirp::Error.not_found("classroom user record not found", argument: "teacher_id")
          end

          if teacher.verified_teacher?
            { teacher_id: req.teacher_id, is_verified: true, reason: "" }
          else
            { teacher_id: req.teacher_id, is_verified: false, reason: "teacher does not have the appropriate coupon" }
          end
        end
      end
    end
  end
end
