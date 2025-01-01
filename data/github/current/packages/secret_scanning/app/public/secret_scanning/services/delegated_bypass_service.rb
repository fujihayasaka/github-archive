# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class DelegatedBypassService
      extend T::Sig
      include SecretScanning::Constants

      BYPASS_REVIEWER_ERROR = "DelegatedBypassServiceBypassReviewerError"
      DelegatedBypassRequestType = T.type_alias { GitHub::Proto::SecretScanning::Types::V1::DelegatedBypassRequest }

      # Adds a delegated bypass reviewer for a given owner
      sig do
        params(
          owner_id: Integer,
          owner_scope: Symbol,
          reviewer_id: Integer,
          reviewer_type: String,
          actor: T.any(User, String, Integer)).returns([T.untyped, T.nilable(String)])
      end
      def self.add_bypass_reviewer(owner_id, owner_scope, reviewer_id, reviewer_type, actor)
        request = {
          bypass_reviewer: {
            owner_id: owner_id,
            owner_scope: owner_scope,
            reviewer_id: reviewer_id,
            reviewer_type: reviewer_type,
          }
        }

        response = GitHub::TokenScanning::Service::Client.new(actor).add_bypass_reviewer(request)

        return nil, "An error has occurred while attempting to add the bypass reviewer." if response.nil?
        return nil, response.error&.msg if response.error.present?
        return nil, "Failed to add bypass reviewer." if response.data.nil? || response.data.bypass_reviewer.nil?

        payload = { actor:, reviewer_id:, reviewer_type: }
        if owner_scope.to_sym == :ORGANIZATION_SCOPE
          payload[:org] = Organization.find_by(id: owner_id)
          event_name = "org_secret_scanning_push_protection_bypass_list.add"
        else
          payload[:repo] = Repository.find_by(id: owner_id)
          event_name = "repository_secret_scanning_push_protection_bypass_list.add"
        end
        GitHub.instrument(event_name, payload)

        [response.data.bypass_reviewer, nil]
      end

      # Removes the delegated bypass reviewer by ID
      sig do
        params(
          bypass_reviewer_id: Integer,
          owner_id: Integer,
          owner_scope: Symbol,
          actor: T.any(User, String, Integer)).returns(T.nilable(String))
      end
      def self.remove_bypass_reviewer(bypass_reviewer_id, owner_id, owner_scope, actor)
        response = GitHub::TokenScanning::Service::Client.new(actor).remove_bypass_reviewer({ id: bypass_reviewer_id })
        return "An error has occurred while attempting to delete the bypass reviewer." if response.nil?
        return response.error&.msg if response.error.present?

        payload = { actor:, bypass_reviewer_id: }
        if owner_scope.to_sym == :organization
          payload[:org] = Organization.find_by(id: owner_id)
          event_name = "org_secret_scanning_push_protection_bypass_list.remove"
        else
          payload[:repo] = Repository.find_by(id: owner_id)
          event_name = "repository_secret_scanning_push_protection_bypass_list.remove"
        end
        GitHub.instrument(event_name, payload)

        nil
      end

      # Gets the delegated bypass reviewers for a given owner
      sig do
        params(
          owner_scope: Symbol,
          owner_id: Integer,
          actor: T.any(User, String, Integer)).returns([T.nilable(T::Array[SecretScanning::Models::BypassReviewer]), T.nilable(String)])
      end
      def self.get_bypass_reviewers(owner_scope, owner_id, actor)
        request = {}
        case owner_scope
        when :repository
          request[:repository_id] = owner_id
        when :organization
          request[:organization_id] = owner_id
        else
          return nil, "Invalid owner scope. :repository or :organization expected."
        end

        response = GitHub::TokenScanning::Service::Client.new(actor).get_bypass_reviewers(request)

        return nil, "An error has occurred while attempting to retrieve the bypass reviewers." if response.nil?
        return nil, response.error&.msg if response.error.present?
        return nil, "Failed to retrieve bypass reviewers." if response.data.nil? || response.data.bypass_reviewers.nil?

        [response.data.bypass_reviewers.map { |reviewer| from_proto_bypass_reviewer(reviewer) }, nil]
      end

      sig do
        params(
          bypass_reviewers: T::Array[SecretScanning::Models::BypassReviewer],
          reviewers_source: T.any(Repository, Organization),
        ).returns([
          T::Array[Integer],
          T::Array[Integer],
          T::Array[Integer],
        ])
      end
      def self.split_bypass_reviewers_ids_by_type(bypass_reviewers, reviewers_source)
        user_ids = []
        role_ids = []
        team_ids = []
        bypass_reviewers.each do |reviewer|
          case GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType.resolve(T.cast(reviewer.reviewer_type, Symbol))
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::TEAM
            team_ids.push(reviewer.reviewer_id)
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ROLE
            role_ids.push(reviewer.reviewer_id)
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ORG_ADMIN
            # We're going to have to revisit this logic for the org-level experience!!
            unless reviewers_source.owner.nil?
              org_owner = Organization.find_by(id: reviewers_source.owner.id)
              unless org_owner.nil?
                user_ids.concat(org_owner.admin_ids)
              end
            end
          else
            # Shouldn't get here
          end
        end

        [user_ids, team_ids, role_ids]
      end

      sig do
        params(
          role_ids: T::Array[Integer],
          repository: Repository
        ).returns([
          T::Array[User],
          T::Array[Team],
        ])
      end
      def self.get_users_teams_from_role_ids(role_ids, repository)
        users = []
        teams = []

        default_roles = []
        custom_roles = []
        role_ids.each do |role_id|
          role = Role.find_by(id: role_id)
          next if role.nil?
          if role.owner_id.nil? && role.owner_type.nil?
            default_roles.push(role)
          else
            custom_roles.push(role)
          end
        end

        if custom_roles.any?
          users.push(User.where(id: UserRole.where(actor_type: "User", target: repository, role_id: custom_roles).pluck(:actor_id)))
          teams.push(Team.where(id: UserRole.where(actor_type: "Team", target: repository, role_id: custom_roles).pluck(:actor_id)))
        end

        if default_roles.any?
          eligible_user_ids = repository.user_ids_with_privileged_access
          eligible_users = User.batched_scope(:id, values: eligible_user_ids).to_a.index_by(&:id)

          _, user_to_highest_role_mapping = repository.batch_action_and_role_level_for(eligible_users.values)

          user_to_highest_role_mapping.each do |user_id, role|
            user = eligible_users[user_id]
            permissions = Repository.permissions_hash(role)

            default_roles.each do |default_role|
              next unless permissions[Team::ABILITIES_TO_PERMISSIONS[default_role.name].to_sym]

              users.push(user)
              break
            end
          end
        end

        [users.flatten.uniq, teams.flatten.uniq]
      end

      # Gets users who can approve delegated bypass requests
      sig do
        params(
          repository: Repository,
          actor: T.any(User, String, Integer)).returns([
            T.nilable(T::Array[User]),
            T.nilable(T::Array[Team]),
            T.nilable(String),
          ])
      end
      def self.get_bypass_reviewer_users_teams(repository, actor)
        owner_id = repository.id
        owner_scope = :repository
        if SecretScanning::Features::Repo::DelegatedBypass.new(repository).enabled_by_organization?
          owner_id = repository.organization&.id
          owner_scope = :organization
        end

        bypass_reviewers, error_message = get_bypass_reviewers(owner_scope, T.must(owner_id), actor)

        if error_message
          Failbot.report(SecretScanning::Errors::Error.new(error_message), app: FAILBOT_APP_NAME, owner_scope: owner_scope, owner_id: owner_id)
          return [nil, nil, error_message]
        end

        if bypass_reviewers.nil? || bypass_reviewers.empty?
          return [nil, nil, nil]
        end

        user_ids, team_ids, role_ids = split_bypass_reviewers_ids_by_type(bypass_reviewers, repository)

        users = User.where(id: user_ids).to_a

        role_users, teams = SecretScanning::Services::DelegatedBypassService.get_users_teams_from_role_ids(role_ids, repository)
        users.concat(role_users) if role_users.any?
        teams.concat(Team.where(id: team_ids).to_a) if team_ids.any?

        [users.flatten.uniq, teams.flatten.uniq, nil]
      end

      sig { params(repo: Repository, actor: T.any(User, PublicKey),).returns(T::Array[DelegatedBypassRequestType]) }
      def self.get_delegated_bypass_requests(repo, actor)
        exemptions = Exemptions::Public.requests_for_repository(T.must(repo.id), T.must(actor.id), "approved", include_responses: true)
        delegated_bypass_requests = exemptions.map do |exemption|
          if exemption[:metadata].nil?
            Failbot.report(SecretScanning::Errors::Error.new("ExemptionRequest is missing metadata"), app: FAILBOT_APP_NAME, repository_id: repo.id, exemption_request_id: exemption[:id])
            next
          end
          GitHub::Proto::SecretScanning::Types::V1::DelegatedBypassRequest.new(
            placeholder_ksuid: exemption[:resource_identifier],
            exemption_request_id: exemption[:id],
            expires_at: Google::Protobuf::Timestamp.new(seconds: exemption[:expires_at].to_i),
            reason: ui_reason_to_enum(exemption[:metadata]["reason"])
          )
        end
        delegated_bypass_requests.compact
      end

      sig { params(reason: String).returns(Integer) }
      def self.ui_reason_to_enum(reason)
        case reason
        when "false_positive"
          GitHub::Proto::SecretScanning::Types::V1::BypassReason::BYPASS_REASON_FALSE_POSITIVE
        when "tests"
          GitHub::Proto::SecretScanning::Types::V1::BypassReason::BYPASS_REASON_USED_IN_TESTS
        when "fixed_later"
          GitHub::Proto::SecretScanning::Types::V1::BypassReason::BYPASS_REASON_WILL_FIX_LATER
        else
          GitHub::Proto::SecretScanning::Types::V1::BypassReason::BYPASS_REASON_UNKNOWN
        end
      end

      # This method checks if a given reviewer is a valid option to be added to the bypass reviewer list
      # of the given organization (or its child repository)
      sig { params(reviewer_id: Integer, reviewer_type: String, organization: Organization).returns(T::Boolean) }
      def self.is_valid_reviewer?(reviewer_id, reviewer_type, organization)
        case reviewer_type
        when "TEAM"
          return true unless organization.teams.find_by(id: reviewer_id, privacy: :closed).nil?
        when "ROLE"
          role = Role.find_by(id: reviewer_id)
          return false if role.nil?

          if role.owner_id.present? # custom role
            return true if role.owner_id == organization.id
          else # default role
            return true if role == RepositoryRole.admin_role
            return true if role == RepositoryRole.maintain_role
          end
        when "ORG_ADMIN"
          # Right now, the org admin role is hardcoded in the component with a default ID = 1.
          return true if reviewer_id == 1
        end
        false
      end

      # This method confirms whether the given user can review bypass requests for the given repository
      sig { params(repository: Repository, user: T.any(User, PublicKey)).returns(T::Boolean) }
      def self.can_review_bypass_request?(repository, user)
        return false if user.is_a?(PublicKey)

        return true if repository.has_repo_delegated_bypass_fgp?(user)

        return true if repository.has_org_delegated_bypass_fgp?(user)

        reviewers_source = repository
        reviewers_scope = :repository
        if SecretScanning::Features::Repo::DelegatedBypass.new(reviewers_source).enabled_by_organization?
          reviewers_source = repository.owner
          reviewers_scope = :organization
        end

        bypass_reviewers, error_message = self.get_bypass_reviewers(reviewers_scope, T.must(reviewers_source&.id), T.must(user.id))
        if bypass_reviewers.nil? || error_message
          Failbot.report(SecretScanning::Errors::Error.new("Could not get bypass reviewers for repo"), app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: user.id)
          return false
        end
        bypass_reviewers.each do |reviewer|
          case GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType.resolve(T.cast(reviewer.reviewer_type, Symbol))
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::TEAM
            team = Team.find_by(id: reviewer.reviewer_id)
            if team.nil?
              Failbot.report(SecretScanning::Errors::Error.new("Could not find team for bypass reviewer"), app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: user.id, team_id: reviewer.reviewer_id)
              next
            end
            return true if team.members.include?(user)
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ROLE
            role = Role.find_by(id: reviewer.reviewer_id)
            if role.nil?
              Failbot.report(SecretScanning::Errors::Error.new("Could not find role for bypass reviewer"), app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: user.id, role_id: reviewer.reviewer_id)
              next
            end
            default_role = Team::ABILITIES_TO_PERMISSIONS.has_key?(role.name)
            if default_role
              # This is a default role, so check the repo permissions hash
              permissions = repository.permissions_hash_for(actor: user)
              return true if permissions.fetch(Team::ABILITIES_TO_PERMISSIONS[role.name].to_sym, nil)
            else
              # This is a custom role, so query the DB
              query = UserRole.where(role_id: reviewer.reviewer_id, target_type: "Repository", target_id: repository.id)
              matches = query
                .where(actor_type: "Team", actor_id: user.teams.pluck(:id)) # Custom role assigned to team user is member of
                .or(query.where(actor_type: "User", actor_id: user.id))     # Custom role assigned to user

              matches.each do |match|
                if match.actor_type == "Team"
                  return true if Team.find_by(id: match.actor_id)&.members.include?(user)
                elsif match.actor_type == "User"
                  return true if match.actor_id == user.id
                end
              end
            end
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ORG_ADMIN
            org_owner = repository.owner
            return true if !org_owner.nil? && org_owner.adminable_by?(user)
          else
            # Shouldn't get here
            Failbot.report(SecretScanning::Errors::Error.new("Unknown bypass reviewer type"), app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: user.id, reviewer_type: reviewer.reviewer_type)
          end
        end
        false
      end

      sig do
        params(
          source: T.any(Repository, Organization),
          current_user: User,
          params: ActionController::Parameters)
        .returns(T::Array[T::Hash[T.untyped, T.untyped]])
      end
      def self.suggested_bypass_reviewers(source, current_user, params)
        suggestions = RulesEngine::Suggestions.bypass_actors_for(
          source,
          current_user,
          query: params[:q].blank? ? nil : params[:q],
          exclude_integrations: true,
        )
        # For now, we are only allowing the "repo admin" default role as a bypass reviewer.
        # This is because we don't yet send emails for ExemptionRequests for default roles.
        grouped = suggestions.group_by { |suggestion| suggestion[:actorType] }
        filtered_roles = if !grouped[:RepositoryRole].nil?
          T.must(grouped[:RepositoryRole]).filter do |role|
            role_obj = T.must(RepositoryRole.find_by(id: role[:actorId]))
            next true if role_obj.owner_id && role_obj.base_role_id
            next true if role_obj == RepositoryRole.admin_role
            next true if role_obj == RepositoryRole.maintain_role
            false
          end
        else
          []
        end

        result = [
          *grouped[:OrganizationAdmin],
          *filtered_roles,
          *grouped[:Team],
        ]
      end

      sig { params(repository: Repository, actor: T.any(User, PublicKey)).returns(T::Boolean) }
      def self.use_delegated_bypass_flow(repository, actor)
        # Ensure actor isn't a PublicKey
        return false unless actor.is_a?(User)

        # Delegated Bypass needs to be enabled for the repo
        return false unless SecretScanning::Features::Repo::DelegatedBypass.new(repository).enabled?

        # If the push actor can review their own push, use the regular bypass flow
        return false if can_review_bypass_request?(repository, actor)

        # If the reviewer list is empty, revert to the regular bypass flow
        reviewers_source = repository
        reviewers_scope = :repository
        if SecretScanning::Features::Repo::DelegatedBypass.new(reviewers_source).enabled_by_organization?
          reviewers_source = repository.owner
          reviewers_scope = :organization
        end
        reviewers, err = get_bypass_reviewers(reviewers_scope, T.must(T.must(reviewers_source).id), actor)

        return false unless err.nil?
        return false if reviewers.nil?
        return false if reviewers.length == 0
        true
      end

      sig { params(reviewer: GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer).returns(SecretScanning::Models::BypassReviewer) }
      def self.from_proto_bypass_reviewer(reviewer)
        SecretScanning::Models::BypassReviewer.new(
          id: reviewer.id,
          owner_id: reviewer.owner_id,
          owner_scope: reviewer.owner_scope,
          reviewer_id: reviewer.reviewer_id,
          reviewer_type: reviewer.reviewer_type,
        )
      end
    end
  end
end
