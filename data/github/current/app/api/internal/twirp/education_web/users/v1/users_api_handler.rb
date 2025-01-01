# typed: true
# frozen_string_literal: true

require "monolith-twirp-education_web-users"

module Api::Internal::Twirp::EducationWeb
  module Users
    module V1
      # Handler for the MonolithTwirp::Classroom::Users::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["education_web"]
        handles_service MonolithTwirp::EducationWeb::Users::V1::UsersAPIService
        connected_to_writing_for(
          :add_dashboard_notice,
          :get_user_details,
          :get_users_contributing_days,
          :has_two_factor_auth,
          :invite_user_to_repository,
          :is_spammy_user,
          :remove_user_from_repository,
          :replace_all_topics_on_user_repository,
          :set_user_coupon,
          :update_users_repository_starred_status
        )

        include UrlHelper

        DISCUSSIONS_REPO_RATE_LIMIT = 5_000

        # Public: Implementation of the GetUsercoupon Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::GetUserCouponRequest.
        # env - The Twirp environment as a Hash.

        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::GetUserCouponResponse, or a Twirp::Error.
        def get_user_coupon(req, env)
          get_user req do |user|
            { result: build_active_user_coupon(user) }
          end
        end

        # Public: Implementation of the SetUsercoupon Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::GetUserCouponRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::SetUserCouponResponse, or a Twirp::Error.
        def set_user_coupon(req, env)
          get_user req do |user|
            return { success: false, error: "User has been suspended" } if user.suspended?

            if req.code.blank?
              user.expire_active_coupon
              return { success: true, error: "" }
            end

            to_user_id = id_argument(req.to_user_id)
            unless to_user_id
              return Twirp::Error.invalid_argument("must be non-empty", argument: "to_user_id")
            end

            actor = User.find_by(id: to_user_id)
            return Twirp::Error.not_found("user not found", argument: "to_user_id") unless actor

            if user.has_an_active_coupon?
              # we want to ensure that an active coupon gets expired correctly if it exists, but we don't
              # want to notify the user since we're replacing it with another valid coupon
              user.expire_active_coupon(quiet: true)
            end

            if user.redeem_coupon(req.code, validate_active_coupon: false, actor: actor, allow_reuse: true)
              { success: true, error: "" }
            else
              { success: false, error: user.errors.full_messages.join(", ") }
            end
          end
        end

        # Public: Implementation of the GetUserClassroomAssignments Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::GetUserClassroomAssignmentsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::GetUserClassroomAssignmentsResponse, or a Twirp::Error.
        def get_user_classroom_assignments(req, env)
          get_user req do |user|
            { results: build_user_classroom_assignments(user) }
          end
        end

        # Public: Implementation of the InviteUserToRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::InviteUserToRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::InviteUserToRepositoryResponse, or a Twirp::Error.
        def invite_user_to_repository(req, env)
          Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless req.repository_id
          Twirp::Error.invalid_argument("must be non-empty", argument: "invitee_id") unless req.invitee_id
          Twirp::Error.invalid_argument("must be non-empty", argument: "inviter_id") unless req.inviter_id

          repository = ::Repositories::Public.find_active(req.repository_id)
          return { success: false, error: "Repository not found" } unless repository

          # "today" is OK here, as its our own rate limit, not the 24 hour limit set on the RateLimitOverride found below
          count = RepositoryInvitation.where(created_at: Date.today, repository_id: repository.id).count
          if count >= DISCUSSIONS_REPO_RATE_LIMIT
            return { success: false, error: "Already invited #{DISCUSSIONS_REPO_RATE_LIMIT} today" }
          end

          invitee = User.find_by(id: req.invitee_id)
          return { success: false, error: "Invitee not found" } unless invitee
          return { success: false, error: "Invitee not a candidate for invitation" } unless invitee.coupon&.code.to_s.start_with?("faculty-")

          inviter = User.find_by(id: req.inviter_id)
          return { success: false, error: "Inviter not found" } unless inviter

          # Set the override, if its not already set. This will give us 24 hours of override
          unless RepositoryInvitationRateLimitOverride.overridden?(repository.id)
            RepositoryInvitationRateLimitOverride.override!(repository.id)
          end

          result = RepositoryInvitation.invite_to_repo(invitee, inviter, repository, action: :read)

          if result[:success]
            { success: true, error: "" }
          elsif result[:errors][:base].include?("User has already been invited") || result[:errors][:base].include?("User is already a collaborator")
            { success: true, error: "" }
          else
            { success: false, error: result[:errors][:base].join(", ") }
          end
        end

        # Public: Implementation of the RemoveUserFromRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::RemoveUserFromRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::RemoveUserFromRepositoryResponse, or a Twirp::Error.
        def remove_user_from_repository(req, env)
          Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless req.repository_id
          Twirp::Error.invalid_argument("must be non-empty", argument: "removee_id") unless req.removee_id
          Twirp::Error.invalid_argument("must be non-empty", argument: "remover_id") unless req.remover_id

          repository = ::Repositories::Public.find_active(req.repository_id)
          return { success: false, error: "Repository not found" } unless repository

          removee = User.find_by(id: req.removee_id)
          return { success: false, error: "Removee not found" } unless removee

          remover = User.find_by(id: req.remover_id)
          return { success: false, error: "Remover not found" } unless remover

          if repository.member?(removee)
            repository.remove_member(removee, remover)
            return { success: true, error: "" }
          end

          repository_invitation = RepositoryInvitation
            .find_by(invitee_id: removee.id, inviter_id: remover.id, repository_id: repository.id)

          if repository_invitation && !repository_invitation.cancel!(actor: remover)
            return { success: false, error: "Invitation failed to cancel" }
          end

          { success: true, error: "" }
        end

        # Public: Implementation of the ReplaceAllTopicsOnUserRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::ReplaceAllTopicsOnUserRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::ReplaceAllTopicsOnUserRepositoryResponse, or a Twirp::Error.
        def replace_all_topics_on_user_repository(req, env)
          Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless req.repository_id
          Twirp::Error.invalid_argument("must be non-empty", argument: "user_id") unless req.user_id
          Twirp::Error.invalid_argument("must be non-empty", argument: "topics") unless req.topics

          invalid_names = req.topics.reject { |name| Topic.valid_name?(name) }
          return { success: false, error: "Invalid topic names: #{invalid_names.join(", ")}"  } if invalid_names.any?

          repository = ::Repositories::Public.find_active(req.repository_id)
          return { success: false, error: "Repository not found" } unless repository

          user = User.find_by(id: req.user_id)
          return { success: false, error: "User not found" } unless user

          return { success: false, error: "User does not have permission to update the topics" } unless repository.can_manage_topics?(user)

          if repository.update_topics(req.topics, user: user)
            { success: true, error: "" }
          else
            { success: false, error: "Failed to update topics" }
          end
        end

        # Public: Implementation of the IsSpammyUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::IsSpammyUserReqeust.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::IsSpammyUserResponse, or a Twirp::Error.
        def is_spammy_user(req, env)

          user_ids = req.user_ids.to_a.reject(&:blank?)
          Twirp::Error.invalid_argument("must be non-empty", argument: "user_ids") unless user_ids.present?

          users = User.where(id: user_ids)
          results = users.map do |user|
            {
              user_id: user.id,
              spammy: user.spammy?
            }
          end

          { results: results }
        end

        # Public: Implementation of the UpdateUsersRepositoryStarredStatus Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::UpdateUsersRepositoryStarredStatusRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::UpdateUsersRepositoryStarredStatusResponse, or a Twirp::Error.
        def update_users_repository_starred_status(req, env)
          Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless req.repository_id
          Twirp::Error.invalid_argument("must be non-empty", argument: "user_id") unless req.user_id
          Twirp::Error.invalid_argument("must be non-empty", argument: "action_type") unless req.action_type

          # action type 0 means unstar and 1 means star
          is_valid_action_type = req.action_type == 0 || req.action_type == 1
          return { success: false, error: Error::Messages::INVALID_ACTION_TYPE  } unless is_valid_action_type

          repository = ::Repositories::Public.find_active(req.repository_id)
          return { success: false, error: Error::Messages::REPOSITORY_NOT_FOUND } unless repository

          return { success: false, error: Error::Messages::REPOSITORY_NOT_PUBLIC } unless repository.public?

          user = User.find_by(id: req.user_id)
          return { success: false, error: Error::Messages::USER_NOT_FOUND } unless user

          if req.action_type == 1
            if user.star(repository)
              { success: true, error: "", count: repository.calculate_stargazer_count }
            else
              { success: false, error: Error::Messages::CAN_NOT_STAR }
            end
          else
            if user.unstar(repository)
              { success: true, error: "", count: repository.calculate_stargazer_count }
            else
              { success: false, error: Error::Messages::CAN_NOT_UNSTAR }
            end
          end
        end

        # Public: Implementation of the GetUserOwnsRepo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::GetUserOwnsRepoRequest
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::GetUserOwnsRepoResponse, or a Twirp::Error.
        def get_user_owns_repo(req, env)
          get_user req do |user|
            { owns_a_repo: owns_a_repo?(user) }
          end
        end

        # Public: Implementation of the GetUserListRepositories Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::GetUserListRepositoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::GetUserListRepositoriesResponse, or a Twirp::Error.
        def get_user_list_repositories(req, env)
          get_user req do |user|
            build_user_list_repositories(user, req.list_name)
          end
        end

        # Public: Implementation of the HasProfileReadme Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::HasProfileReadmeRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::HasProfileReadmeResponse, or a Twirp::Error.
        def has_profile_readme(req, env)
          get_user req do |user|
            has_visible_profile_readme = user.profile_readme_visible?

            if has_visible_profile_readme
              path = user.profile_readme.path
              has_profile_readme_commits_by_user = has_profile_readme_commits_by_user?(user, path)
            end

            result = has_visible_profile_readme && has_profile_readme_commits_by_user

            {
              has_profile_readme: result,
              is_visible: has_visible_profile_readme,
              has_commits: has_profile_readme_commits_by_user
            }
          end
        end

        # Public: Implementation of the HasClonedTemplateAndPushedToClone Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::HasClonedTemplateAndPushedToCloneRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::HasClonedTemplateAndPushedToCloneResponse, or a Twirp::Error.
        def has_cloned_template_and_pushed_to_clone(req, env)
          get_user req do |user|
            template_repo_id = req.template_repository_id

            # Get the most recently created clones of the specified template that belong to this user.
            # Limit is intentionally chosen to prevent iterating through unnecessary records.
            clone_repos = RepositoryClone
              .where(template_repository_id: template_repo_id)
              .select(:clone_repository_id)
              .order(created_at: :desc)
              .where(cloning_user_id: user.id)
              .limit(5)

            # `true` when a cloner has authored a commit on any of their clones' default branch.
            result = clone_repos.any? do |clone_repo|
              repo = Repositories::Public.get_active_or_deleted!(clone_repo.clone_repository_id)
              repo.paged_commits(repo.default_branch, 1, 1, { author: user }).any?
            end

            { has_cloned_template_and_pushed_to_clone: result }
          end
        end

        # Public: Implementation of the GetUserDetails Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::GetUserDetailsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::EducationWeb::Users::V1::GetUserDetailsResponse, or a Twirp::Error.
        def get_user_details(req, env)
          user_id = req.user_github_id
          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("User not found", argument: "user_id") unless user

          billing_profile = AccountScreeningProfile.find_by(owner_id: user_id)
          user_github_identifier = user.login
          user_name = user.profile_name
          created_at = user.created_at.to_s

          {
            github_identifier: user_github_identifier,
            github_name: user_name,
            github_billing_first_name: billing_profile&.first_name,
            github_billing_last_name: billing_profile&.last_name,
            github_billing_address1: billing_profile&.address1,
            github_billing_city: billing_profile&.city,
            github_billing_region: billing_profile&.region,
            github_billing_country_code: billing_profile&.country_code,
            github_created_at: created_at,
          }
        end

        def has_two_factor_auth(req, env)
          user_id = req.user_github_id

          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("User not found", argument: "user_id") unless user

          {
            has_two_factor_auth_enabled: user.two_factor_authentication_enabled?,
            two_factor_login_preference: user.two_factor_credential&.login_preference
          }
        end

        def add_dashboard_notice(req, env)
          user_id = req.user_id

          return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id") unless user_id.present?

          user = User.find_by(id: user_id)
          return Twirp::Error.not_found("User not found", argument: "user_id") unless user

          if user.activate_notice(UserNotice::DASHBOARD_GLOBAL_CAMPUS_NOTICE)
            { success: true, error: "" }
          else
            { success: false, error: user.errors.full_messages.join(", ") }
          end
        end

        # Handles the GetUserUnderlineSetting RPC call. It retrieves the underline setting
        # for a user specified by the user_id in the request.
        #
        # req - The GetUserUnderlineSettingRequest object containing the user_id.
        # _ - The RPC call context (unused in this method).
        #
        # Returns a MonolithTwirp::EducationWeb::Users::V1::GetUserUnderlineSettingResponse object
        # containing the user's underline setting as a boolean.
        # If the user is not found, a Twirp error is raised.
        def get_user_underline_setting(req, _)
          user_id = req.user_github_id

          user = User.find_by(id: user_id)

          # Raise a Twirp error if the user is not found
          return Twirp::Error.not_found("User with ID #{user_id} not found") unless user

          underline_enabled = user.settings.get(:link_underlines)

          MonolithTwirp::EducationWeb::Users::V1::GetUserUnderlineSettingResponse.new(underline_enabled: underline_enabled)
        end

        private

        # Private: Returns a hash for constructing a MonolithTwirp::EducationWeb::Users::V1::UserCoupon.
        #
        # user - User record
        #
        # Returns an array of Hash objects with user data that matches the
        # Twirp definition.
        def build_active_user_coupon(user)
          coupon = user.coupon

          {
            code: coupon&.code,
            plan: coupon&.plan,
            duration: coupon&.duration,
            expires_at: user.coupon_redemption&.expires_at.to_i,
            limit: coupon&.limit
          }
        end

        # Private: Returns a hash for constructing a GitHub::Proto::Users::V1::UserClassroomAssignmentListItem.
        #
        # user - User record
        #
        # Returns an array of Hash objects with user data that matches the
        # Twirp definition.
        def build_user_classroom_assignments(user)
          affiliations = [:owned, :direct, :indirect]
          # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          associated_repository_ids = user.associated_repository_ids(including: affiliations, include_indirect_forks: false)
          # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
          assignments = ClassroomRepository.includes(:repository).where(repository_id: associated_repository_ids)

          assignments.map do |assignment|
            {
              classroom_name: assignment.classroom_name,
              assignment_name: assignment.assignment_name,
              assignment_type: assignment.assignment_type,
              deadline: assignment.deadline.to_i,
              url: repository_url(assignment.repository),
              assignment_id: assignment.classroom_assignment_id
            }
          end
        end

        # extract the user from the request and validate. The user is passed to the block if found and valid
        #
        # req - The Twirp request as a MonolithTwirp::EducationWeb::Users::V1::GetUserClassroomAssignmentsRequest.
        #
        # Returns the result of the given block or a Twirp::Error
        def get_user(req, &block)
          user_id = id_argument(req.user_id)
          unless user_id
            return Twirp::Error.invalid_argument("must be non-empty", argument: "user_id")
          end

          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user not found", argument: "user_id") unless user
          block.call(user)
        end

        # Private: Returns whether the passed user owns a repo
        #
        # user - User record
        #
        # Returns a boolean
        def owns_a_repo?(user)
          Repository.where(owner_id: user.id).limit(1).present?
        end

        # Private: Return a hash with an array of repository ids and a boolean to show if user has the specified list
        #
        # user - User record
        # list_name - String name of the list
        #
        # Returns a hash with 2 keys: repository_ids and has_user_list
        def build_user_list_repositories(user, list_name)
          list = user.lists.find_by(name: list_name)

          repository_ids = list ? list.repositories.pluck(:id) : []

          { repository_ids: repository_ids, has_user_list: list.present? }
        end

        # Private: Returns whether the user's Profile README has commits made by that user
        #
        # user - User record
        # path - path of Profile README TreeEntry
        #
        # Returns a boolean
        def has_profile_readme_commits_by_user?(user, path)
          repo = Repository.nwo "#{user}/#{user}"
          page = 1 # return the first page of commits
          commits_per_page = 1 # return 1 commit matching the path and author

          repo.paged_commits(repo.default_branch, page, commits_per_page, { path: path, author: user }).any?
        end
      end
    end
  end
end
