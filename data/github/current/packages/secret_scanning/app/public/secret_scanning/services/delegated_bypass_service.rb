# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class DelegatedBypassService
      include SecretScanning::Constants

      BYPASS_REVIEWER_ERROR = "DelegatedBypassServiceBypassReviewerError"
      DelegatedBypassRequestType = T.type_alias { GitHub::Proto::SecretScanning::Types::V1::DelegatedBypassRequest }

      # Adds a delegated bypass reviewer for a given owner
      sig do
        params(
          owner_id: Integer,
          owner_scope: Symbol,
          security_configuration_id: T.nilable(Integer),
          reviewer_id: Integer,
          reviewer_type: String,
          actor: T.any(User, String, Integer)).returns([T.untyped, T.nilable(String)])
      end
      def self.add_bypass_reviewer(owner_id, owner_scope, security_configuration_id, reviewer_id, reviewer_type, actor)
        request = {
          bypass_reviewer: {
            owner_id: owner_id,
            owner_scope: owner_scope,
            security_configuration_id: security_configuration_id,
            reviewer_id: reviewer_id,
            reviewer_type: reviewer_type,
          }
        }

        response = GitHub::TokenScanning::Service::Client.new(actor).add_bypass_reviewer(request)

        return nil, "An error has occurred while attempting to add the bypass reviewer." if response.nil?
        return nil, response.error&.msg if response.error.present?
        return nil, "Failed to add bypass reviewer." if response.data.nil? || response.data.bypass_reviewer.nil?

        payload = { actor:, reviewer_id:, reviewer_type:, security_configuration_id: }
        if owner_scope.to_sym == :ORGANIZATION_SCOPE
          payload[:org] = Organization.find_by(id: owner_id)
          event_name = "org_secret_scanning_push_protection_bypass_list.add"
        else
          payload[:repo] = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
            Repositories.domain.by_id(owner_id)
          else
            Repository.find_by(id: owner_id)
          end
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
          payload[:repo] = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
            Repositories.domain.by_id(owner_id)
          else
            Repository.find_by(id: owner_id)
          end
          event_name = "repository_secret_scanning_push_protection_bypass_list.remove"
        end
        GitHub.instrument(event_name, payload)

        nil
      end

      # Gets the delegated bypass reviewers for a given owner
      sig do
        params(
          source: T.any(Repository, Organization, Business),
          actor: T.any(User, String, Integer),
          security_configuration_id: T.nilable(Integer),
        ).returns([T.nilable(T::Array[SecretScanning::Models::BypassReviewer]), T.nilable(String)])
      end
      def self.get_bypass_reviewers(source, actor, security_configuration_id: nil)
        request = {}
        if source.is_a?(Organization)
          request[:organization_id] = source.id
        elsif source.is_a?(Business)
          request[:business_id] = source.id
        elsif source.is_a?(Repository)
          if SecretScanning::Features::Repo::DelegatedBypass.new(source).enabled_by_security_configuration?
            security_config_target_type = source.security_configuration&.target_type
            if security_config_target_type == "Business"
              request[:business_id] = source.security_configuration&.target_id
              security_configuration_id = source.security_configuration&.id
            elsif security_config_target_type == "User"
              # This means organization, because orgs are users under the hood
              request[:organization_id] = source.security_configuration&.target_id
              security_configuration_id = source.security_configuration&.id
            else
              GitHub.logger.info("Invalid security configuration target type", "target_type": security_config_target_type, "repo.id": source.id)
            end
          else
            request[:repository_id] = source.id
          end
        else
          return nil, "Invalid source. Repository, Organization, or Business expected."
        end

        request[:security_configuration_id] = security_configuration_id if security_configuration_id

        response = GitHub::TokenScanning::Service::Client.new(actor).get_bypass_reviewers(request)

        return nil, "An error has occurred while attempting to retrieve the bypass reviewers." if response.nil?
        return nil, response.error&.msg if response.error.present?
        return nil, "Failed to retrieve bypass reviewers." if response.data.nil? || response.data.bypass_reviewers.nil?

        [
          response.data.bypass_reviewers
            .sort { |a, b| a.id <=> b.id }
            .uniq { |reviewer| { type: reviewer.reviewer_type, reviewer_id: reviewer.reviewer_id } }
            .map { |reviewer| from_proto_bypass_reviewer(reviewer) },
          nil,
        ]
      end

      sig do
        params(
          source: T.any(Repository, Organization, Business),
          security_configuration_id: T.nilable(Integer),
          bypass_reviewers: T::Array[SecretScanning::Models::BypassReviewer],
          actor: T.any(User, String, Integer),
        ).returns([T.nilable(T::Array[SecretScanning::Models::BypassReviewer]), T.nilable(String)])
      end
      def self.update_bypass_reviewers_for_source(source, security_configuration_id, bypass_reviewers, actor)
        request = { bypass_reviewers:, security_configuration_id: }
        if source.is_a?(Organization)
          request[:organization_id] = source.id
        elsif source.is_a?(Business)
          request[:business_id] = source.id
        elsif source.is_a?(Repository)
          if SecretScanning::Features::Repo::DelegatedBypass.new(source).enabled_by_security_configuration?
            return nil, "Invalid update. Cannot update repository bypass reviewers when delegated bypass is enabled by organization or security configuration."
          end
          request[:repository_id] = source.id
        else
          return nil, "Invalid source. Repository or Organization expected."
        end
        response = GitHub::TokenScanning::Service::Client.new(actor).update_bypass_reviewers_for_source(request)

        return nil, "An error has occurred while attempting to update the bypass reviewers." if response.nil?
        return nil, response.error&.msg if response.error.present?
        return nil, "Failed to update bypass reviewers." if response.data.nil? || response.data.bypass_reviewers.nil?

        payload = { actor:, security_configuration_id:, bypass_reviewers:, bulk_update: true }
        if source.is_a?(Organization)
          payload[:org] = Organization.find_by(id: source.id)
          event_name = "org_secret_scanning_push_protection_bypass_list.add"
        else
          payload[:repo] = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
            Repositories.domain.by_id(source.id)
          else
            Repository.find_by(id: source.id)
          end
          event_name = "repository_secret_scanning_push_protection_bypass_list.add"
        end
        GitHub.instrument(event_name, payload)

        [response.data.bypass_reviewers.map { |reviewer| from_proto_bypass_reviewer(reviewer) }, nil]
      end

      sig do
        params(
          source: T.any(Repository, Organization),
          security_configuration_id: T.nilable(Integer),
          actor: T.any(User, String, Integer),
        ).returns(T.nilable(String))
      end
      def self.remove_bypass_reviewers_for_source(source, security_configuration_id, actor)
        request = { security_configuration_id: }
        if source.is_a?(Organization)
          request[:organization_id] = source.id
        elsif source.is_a?(Repository)
          if SecretScanning::Features::Repo::DelegatedBypass.new(source).enabled_by_security_configuration?
            return "Invalid deletion. Cannot remove repository bypass reviewers when delegated bypass is enabled by organization or security configuration."
          end
          request[:repository_id] = source.id
        else
          return "Invalid source. Repository or Organization expected."
        end
        response = GitHub::TokenScanning::Service::Client.new(actor).remove_bypass_reviewers_for_source(request)
        return "An error has occurred while attempting to delete the bypass reviewers for this source." if response.nil?
        return response.error&.msg if response.error.present?

        payload = { actor:, security_configuration_id:, bulk_update: true }
        if source.is_a?(Organization)
          payload[:org] = Organization.find_by(id: source.id)
          event_name = "org_secret_scanning_push_protection_bypass_list.remove"
        else
          payload[:repo] = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
            Repositories.domain.by_id(source.id)
          else
            Repository.find_by(id: source.id)
          end
          event_name = "repository_secret_scanning_push_protection_bypass_list.remove"
        end
        GitHub.instrument(event_name, payload)

        nil
      end

      sig do
        params(
          bypass_reviewers: T::Array[SecretScanning::Models::BypassReviewer],
          reviewers_source: T.any(Repository, Organization, Business),
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
        if reviewers_source.is_a?(Repository) && reviewers_source.owner.present? && reviewers_source.owner.is_a?(Organization)
          org_owner = T.cast(reviewers_source.owner, Organization)
        end
        enterprise_owners = []
        if reviewers_source.is_a?(Business)
          enterprise_owners = reviewers_source.owners || []
        elsif reviewers_source.is_a?(Organization)
          enterprise_owners = reviewers_source.business&.owners || []
        elsif reviewers_source.is_a?(Repository)
          enterprise_owners = reviewers_source.business&.owners || []
        end

        bypass_reviewers.each do |reviewer|
          case GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType.resolve(T.cast(reviewer.reviewer_type, Symbol))
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::TEAM
            team_ids.push(reviewer.reviewer_id)
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ROLE
            role_ids.push(reviewer.reviewer_id)
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ORG_ADMIN
            # We're going to have to revisit this logic for the org-level experience!!
            unless org_owner.nil?
              user_ids.concat(org_owner.admin_ids)
            end
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ENTERPRISE_OWNER
            user_ids.concat(enterprise_owners.map(&:id))
          else
            # Shouldn't get here
          end
        end

        [user_ids, team_ids, role_ids]
      end

      sig do
        params(
          role_ids: T::Array[Integer],
          repository: Repository,
        ).returns([
          T::Array[User],
          T::Array[Team],
        ])
      end
      def self.get_users_teams_from_role_ids(role_ids, repository)
        users = []
        teams = []

        default_roles, custom_roles = Authz.domain.roles.with_ids(role_ids).partition(&:preset?)

        if custom_roles.any?
          users.push(User.where(id: UserRole.where(actor_type: "User", target: repository, role_id: custom_roles).pluck(:actor_id)))
          teams.push(Team.with_business_teams.where(id: UserRole.where(actor_type: %w[Team BusinessTeam], target: repository, role_id: custom_roles).pluck(:actor_id)))
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
        bypass_reviewers, error_message = get_bypass_reviewers(repository, actor)

        if error_message
          Failbot.report(SecretScanning::Errors::Error.new(error_message), app: FAILBOT_APP_NAME, repository: repository)
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

      sig { params(repo: Repository, actor: T.any(User, PublicKey)).returns(T::Array[DelegatedBypassRequestType]) }
      def self.get_delegated_bypass_requests(repo, actor)
        exemptions = Exemptions::Public.requests_for_repository(repo.id, actor.id, SecretScanning::ExemptionConstants::EXEMPTION_REQUEST_TYPE, "approved", include_responses: true)
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
        when "ENTERPRISE_OWNER"
          # Right now, the enterprise owner role is hardcoded in the component with a default ID = 1
          return true if reviewer_id == 1
        end
        false
      end

      # This method confirms whether the given user can review bypass requests for the given repository and why
      sig { params(repository: Repository, user: T.any(User, PublicKey)).returns([T::Boolean, String]) }
      def self.can_review_bypass_request?(repository, user)
        return false, "requester is a Public Key, not a User" if user.is_a?(PublicKey)

        # We only support delegated bypass for org-owned repos
        return false, "repository is not org-owned" unless repository.owner.present? && T.must(repository.owner).organization?

        org = T.must(repository.owner)
        org_delegated_bypass = SecretScanning::Features::Org::DelegatedBypass.new(T.cast(org, Organization))
        repo_delegated_bypass = SecretScanning::Features::Repo::DelegatedBypass.new(repository)

        if user.can_have_granular_permissions?
          # Programmatic actors (apps) can only review bypass requests if they have write access to the FGR, and if the FF is enabled.
          org_fgr_write_access = org_delegated_bypass.review_fgr_enabled? && org.resources.organization_secret_scanning_bypass_requests.writable_by?(user)
          repo_fgr_write_access = repo_delegated_bypass.review_fgr_enabled? && repository.resources.secret_scanning_bypass_requests.writable_by?(user)
          if org_fgr_write_access
            return true, "user has org review delegated bypass FGR write access"
          elsif repo_fgr_write_access
            return true, "user has repo review delegated bypass FGR write access"
          else
            return false, "user has neither org nor repo review delegated bypass FGR write access"
          end
        end

        return true, "user has repo delegated bypass FGP" if repository.has_repo_delegated_bypass_fgp?(user)

        return true, "user has org delegated bypass FGP" if repository.has_org_delegated_bypass_fgp?(user)

        bypass_reviewers, error_message = self.get_bypass_reviewers(repository, user.id)
        if bypass_reviewers.nil? || error_message
          Failbot.report(SecretScanning::Errors::Error.new("Could not get bypass reviewers for repo"), app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: user.id)
          return false, "could not get bypass reviewers for repo"
        end

        bypass_reviewers.each do |reviewer|
          case GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType.resolve(T.cast(reviewer.reviewer_type, Symbol))
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::TEAM
            team = Team.find_by(id: reviewer.reviewer_id)
            if team.nil?
              GitHub.logger.info("Could not find team for secret scanning bypass reviewer", "repo.id": repository.id, "user.id": user.id, "team.id": reviewer.reviewer_id, "code.function": "can_review_bypass_request?")
              next
            end
            return true, "user is member of team: #{team.name}" if team.members.include?(user)
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ROLE
            role = Role.find_by(id: reviewer.reviewer_id)
            if role.nil?
              GitHub.logger.info("Could not find role for secret scanning bypass reviewer", "repo.id": repository.id, "user.id": user.id, "role.id": reviewer.reviewer_id, "code.function": "can_review_bypass_request?")
              next
            end
            default_role = Team::ABILITIES_TO_PERMISSIONS.has_key?(role.name)
            if default_role
              # This is a default role, so check the repo permissions hash
              permissions = repository.permissions_hash_for(actor: user)
              return true, "user has default role: #{role.name}" if permissions.fetch(Team::ABILITIES_TO_PERMISSIONS[role.name].to_sym, nil)
            else
              query = UserRole.where(role_id: reviewer.reviewer_id, target_type: "Repository", target_id: repository.id)
              user_teams = Orgs.domain.teams.team_ids_by_actor_id_for(actor_type: "User", actor_ids: [user.id])[user.id]
              matches = query
                .where(actor_type: %w[Team BusinessTeam], actor_id: user_teams)  # Custom role assigned to team user is member of
                .or(query.where(actor_type: "User", actor_id: user.id))     # Custom role assigned to user

              matches.each do |match|
                if %w[Team BusinessTeam].include? match.actor_type
                  role_team = Team.with_business_teams.find_by(id: match.actor_id)
                  return true, "user is member of team (#{(role_team.name || "")}) with custom role: #{role.name}" if role_team&.member?(user)
                elsif match.actor_type == "User"
                  return true, "user has custom role: #{role.name}" if match.actor_id == user.id
                end
              end
            end
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ORG_ADMIN
            org_owner = repository.owner
            return true, "user is an org owner" if !org_owner.nil? && org_owner.adminable_by?(user)
          when GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ENTERPRISE_OWNER
            return true, "user is a business owner" if repository.business&.owner?(user)
          else
            # Shouldn't get here
            Failbot.report(SecretScanning::Errors::Error.new("Unknown bypass reviewer type"), app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: user.id, reviewer_type: reviewer.reviewer_type)
          end
        end
        [false, "user is not a bypass reviewer"]
      end

      sig do
        params(
          source: T.any(Repository, Organization, Business),
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
        # For now, we are only allowing the "repo admin" and "maintainer" default roles as bypass reviewers.
        # This is because we don't yet send emails for ExemptionRequests for default roles.
        grouped = suggestions.group_by { |suggestion| suggestion[:actorType] }
        filtered_repo_roles = if !grouped[:RepositoryRole].nil?
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

        result = []

        business = source.is_a?(Business) ? source : source.business

        if grouped[:EnterpriseOwner].present?
          if business.present? && SecretScanning::Features::Business::DelegatedBypass.new(business).enabled_for_security_configuration?
            result.concat(T.must(grouped[:EnterpriseOwner]))
          end
        end

        if grouped[:OrganizationAdmin].present?
          org_admin = T.must(grouped[:OrganizationAdmin])
          org_admin = org_admin.each { |admin| admin[:actorId] = 1 }
          result.concat(org_admin)
        end

        result.concat [
          *filtered_repo_roles,
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
        can_review_bypass_request, _ = can_review_bypass_request?(repository, actor)
        return false if can_review_bypass_request

        # If the reviewer list is empty, revert to the regular bypass flow
        reviewers, err = get_bypass_reviewers(repository, actor)

        # If there's a problem with getting bypass reviewers from TSS, assume that the user is not a reviewer
        # and thus needs the delegated bypass flow. This is a conservative approach to prevent non-privileged users
        # from self-approving. If the user is in fact a reviewer, they can always try their push again.
        return true unless err.nil?

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
          security_configuration_id: reviewer.security_configuration_id,
          reviewer_id: reviewer.reviewer_id,
          reviewer_type: reviewer.reviewer_type,
        )
      end

      sig { params(org: Organization).returns(T::Array[Integer]) }
      def self.get_users_with_fgp_via_custom_roles(org)
        SecretScanning::Util::Authorization.get_users_with_fgp_via_custom_roles_for_org(org, :org_review_and_manage_secret_scanning_bypass_requests)
      end

      sig { params(repository: Repository).returns([T.nilable(T.any(Repository, Organization, Business)), T.nilable(SecurityConfiguration)]) }
      def self.get_delegated_bypass_enablement_scope(repository)
        # Returns:
        # - The entity with delegated bypass enabled, through which the repo inherited the feature
        # - The repo's feature-enabled security configuration, if any.

        repo_delegated_bypass = SecretScanning::Features::Repo::DelegatedBypass.new(repository)
        enabled_by_org_security_configuration = repo_delegated_bypass.enabled_by_security_configuration?
        if enabled_by_org_security_configuration
          org_owner = T.cast(T.must(repository.owner), Organization)
          return [org_owner, repository.security_configuration]
        end

        # Once enablement via enterprise security configurations is supported, we should check for that here too.

        enabled_on_repo_directly = repo_delegated_bypass.enabled?
        if enabled_on_repo_directly
          return [repository, nil]
        end

        [nil, nil]
      end

      sig { params(security_configuration: SecurityConfiguration).returns(T.nilable(Symbol)) }
      def self.get_owner_scope_for_configuration(security_configuration)
        if security_configuration.business?
          :BUSINESS_SCOPE
        elsif security_configuration.organization?
          :ORGANIZATION_SCOPE
        else
          :UNKNOWN_SCOPE
        end
      end

      sig { params(actor_type: String).returns(Symbol) }
      def self.get_reviewer_type_from_actor_type(actor_type)
        case actor_type
        when "Team"
          proto_value = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::TEAM
        when "RepositoryRole"
          proto_value = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ROLE
        when "OrganizationAdmin"
          proto_value = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ORG_ADMIN
        when "BusinessTeam"
          proto_value = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::BUSINESS_TEAM
        when "EnterpriseOwner"
          proto_value = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ENTERPRISE_OWNER
        when "EnterpriseRole"
          proto_value = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::ENTERPRISE_ROLE
        when "Integration"
          proto_value = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::INTEGRATION
        else
          proto_value = GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType::UNKNOWN
        end
        T.must(GitHub::Proto::SecretScanning::Scans::V2::BypassReviewer::BypassReviewerType.lookup(proto_value))
      end

      sig { params(reviewer: SecretScanning::Models::BypassReviewer).returns(T::Hash[Symbol, T.untyped]) }
      def self.security_config_bypass_actor_hash(reviewer)
        ret = {
          id: reviewer.id,
          actorId: reviewer.reviewer_id,
          # These fields are used by the UI
          bypassMode: 0,
          _enabled: true,
          _dirty: false,
        }

        case reviewer.reviewer_type
        when :TEAM
          team = Team.find_by(id: reviewer.reviewer_id)
          if team
            ret[:name] = team.name || ""
          end
          ret[:actorType] = "Team"
        when :ROLE
          role = Role.find_by(id: reviewer.reviewer_id)
          if role
            ret[:name] = role.name || ""
          end
          ret[:actorType] = "RepositoryRole"
        when :ORG_ADMIN
          ret[:name] = "Organization admin"
          ret[:actorType] = "OrganizationAdmin"
        when :BUSINESS_TEAM
          ret[:name] = "Business team: not yet supported"
        when :ENTERPRISE_OWNER
          ret[:name] = "Enterprise owners"
          ret[:actorType] = "EnterpriseOwner"
        when :ENTERPRISE_ROLE
          ret[:name] = "Enterprise role: not yet supported"
        when :INTEGRATION
          ret[:name] = "Enterprise app: not yet supported"
        else
          {}
        end
        ret
      end

      sig { params(reviewer: SecretScanning::Models::BypassReviewer).returns(T::Hash[Symbol, T.untyped]) }
      def self.ui_bypass_reviewer_hash(reviewer)
        display_reviewer = {
          id: reviewer.id,
          actor_id: reviewer.reviewer_id,
          reviewer_type: reviewer.reviewer_type,
          preferred_avatar_url: "",
          name: "",
        }
        case reviewer.reviewer_type
        when :TEAM
          team = Team.find_by(id: reviewer.reviewer_id)
          if team
            display_reviewer[:name] = team.name || ""
            display_reviewer[:preferred_avatar_url] = team.primary_avatar_url
          end
        when :ROLE
          role = Role.find_by(id: reviewer.reviewer_id)
          if role
            display_reviewer[:name] = (role.name == "admin" ? role.target_type + " " + role.name : role.name).capitalize
          end
        when :ORG_ADMIN
          display_reviewer[:name] = "Organization admin"
          display_reviewer[:reviewer_type] = :ROLE
        when :BUSINESS_TEAM
          display_reviewer[:name] = "Enterprise team"
        when :ENTERPRISE_OWNER
          display_reviewer[:name] = "Enterprise owners"
          display_reviewer[:reviewer_type] = :ROLE
        when :ENTERPRISE_ROLE
          display_reviewer[:name] = "Enterprise role"
        when :INTEGRATION
          display_reviewer[:name] = "Enterprise app"
        end
        display_reviewer
      end
    end
  end
end
