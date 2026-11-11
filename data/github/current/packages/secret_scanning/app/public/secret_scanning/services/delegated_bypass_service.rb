# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class DelegatedBypassService
      include SecretScanning::Constants

      BYPASS_REVIEWER_ERROR = "DelegatedBypassServiceBypassReviewerError"
      DelegatedBypassRequestType = T.type_alias { GitHub::Proto::SecretScanning::Types::V1::DelegatedBypassRequest }

      TEAM_REVIEWER_TYPES = T.let(Set.new([:TEAM, :"Enterprise team"]).freeze, T::Set[Symbol])
      ROLE_REVIEWER_TYPES = T.let(Set.new([:ROLE, :"Enterprise role"]).freeze, T::Set[Symbol])
      INTEGRATION_REVIEWER_TYPES = T.let(Set.new([:INTEGRATION]).freeze, T::Set[Symbol])

      # Adds a delegated bypass reviewer for a given owner
      sig do
        params(
          owner_id: Integer,
          owner_scope: Symbol,
          security_configuration_id: T.nilable(Integer),
          bypasser_id: Integer,
          bypasser_type: String,
          actor: T.any(User, String, Integer)).returns([T.untyped, T.nilable(String)])
      end
      def self.add_bypasser(owner_id, owner_scope, security_configuration_id, bypasser_id, bypasser_type, actor)
        bypasser = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser.new(
          owner_id: owner_id,
          owner_scope: owner_scope,
          security_configuration_id: security_configuration_id,
          bypasser_id: bypasser_id,
          bypasser_type: bypasser_type.to_sym,
        )
        request = GitHub::Proto::SecretScanning::Bypassers::V1::AddBypasserRequest.new(
          bypasser: bypasser,
        )

        response = GitHub::TokenScanning::Service::Client.new(actor).add_bypasser(request)

        return nil, "An error has occurred while attempting to add the bypass reviewer." if response.nil?
        return nil, response.error&.msg if response.error.present?
        return nil, "Failed to add bypass reviewer." if response.data.nil? || response.data.bypasser.nil?

        payload = { actor:, reviewer_id: bypasser_id, reviewer_type: bypasser_type, security_configuration_id: }
        if owner_scope.to_sym == :ORGANIZATION_SCOPE
          payload[:org] = Organization.find_by(id: owner_id)
          event_name = "org_secret_scanning_push_protection_bypass_list.add"
        else
          payload[:repo] = Repositories.domain.by_id(owner_id)
          event_name = "repository_secret_scanning_push_protection_bypass_list.add"
        end
        GitHub.instrument(event_name, payload)

        [response.data.bypasser, nil]
      end

      # Removes the delegated bypasser by ID
      sig do
        params(
          bypasser_id: Integer,
          owner_id: Integer,
          owner_scope: Symbol,
          actor: T.any(User, String, Integer)).returns(T.nilable(String))
      end
      def self.remove_bypasser(bypasser_id, owner_id, owner_scope, actor)
        request = GitHub::Proto::SecretScanning::Bypassers::V1::RemoveBypasserRequest.new(id: bypasser_id)
        response = GitHub::TokenScanning::Service::Client.new(actor).remove_bypasser(request)
        return "An error has occurred while attempting to delete the bypass reviewer." if response.nil?
        return response.error&.msg if response.error.present?

        payload = { actor:, bypass_reviewer_id: bypasser_id }
        if owner_scope.to_sym == :ORGANIZATION_SCOPE
          payload[:org] = Organization.find_by(id: owner_id)
          event_name = "org_secret_scanning_push_protection_bypass_list.remove"
        else
          payload[:repo] = Repositories.domain.by_id(owner_id)
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
        ).returns([T.nilable(T::Array[SecretScanning::Models::Bypasser]), T.nilable(String)])
      end
      def self.get_bypassers(source, actor, security_configuration_id: nil)
        request = GitHub::Proto::SecretScanning::Bypassers::V1::GetBypassersRequest.new
        if source.is_a?(Organization)
          request.organization_id = source.id
        elsif source.is_a?(Business)
          request.business_id = source.id
        elsif source.is_a?(Repository)
          if SecretScanning::Features::Repo::DelegatedBypass.new(source).enabled_by_security_configuration?
            security_config_target_type = source.security_configuration&.target_type
            if security_config_target_type == "Business"
              request.business_id = source.security_configuration&.target_id
              security_configuration_id = source.security_configuration&.id
            elsif security_config_target_type == "User"
              # This means organization, because orgs are users under the hood
              request.organization_id = source.security_configuration&.target_id
              security_configuration_id = source.security_configuration&.id
            else
              GitHub.logger.info("Invalid security configuration target type", "target_type": security_config_target_type, "repo.id": source.id)
            end
          else
            request.repository_id = source.id
          end
        else
          return nil, "Invalid source. Repository, Organization, or Business expected."
        end

        request.security_configuration_id = security_configuration_id if security_configuration_id

        response = GitHub::TokenScanning::Service::Client.new(actor).get_bypassers(request)

        return nil, "An error has occurred while attempting to retrieve the bypass reviewers." if response.nil?
        return nil, response.error&.msg if response.error.present?
        return nil, "Failed to retrieve bypass reviewers." if response.data.nil? || response.data.bypassers.nil?

        [
          response.data.bypassers
            .sort { |a, b| a.id <=> b.id }
            .uniq { |bypasser| { type: bypasser.bypasser_type, bypasser_id: bypasser.bypasser_id } }
            .map { |bypasser| SecretScanning::Models::Bypasser.from_proto_bypasser(bypasser) },
          nil,
        ]
      end

      sig do
        params(
          source: T.any(Repository, Organization, Business),
          security_configuration_id: T.nilable(Integer),
          bypassers: T::Array[GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser],
          actor: T.any(User, String, Integer),
        ).returns([T.nilable(T::Array[SecretScanning::Models::Bypasser]), T.nilable(String)])
      end
      def self.update_bypassers_for_source(source, security_configuration_id, bypassers, actor)
        request = GitHub::Proto::SecretScanning::Bypassers::V1::UpdateBypassersForSourceRequest.new(
          bypassers:,
          security_configuration_id:,
        )
        if source.is_a?(Organization)
          request.organization_id = source.id
        elsif source.is_a?(Business)
          request.business_id = source.id
        elsif source.is_a?(Repository)
          delegated_bypass = SecretScanning::Features::Repo::DelegatedBypass.new(source)
          if delegated_bypass.enforced_enabled_by_security_configuration?
            return nil, "Invalid update. Cannot update repository bypass reviewers when delegated bypass is enabled by organization or security configuration."
          end
          if delegated_bypass.enabled_by_security_configuration?
            enable_actor = actor.is_a?(User) ? actor : User.find_by(id: actor)
            return nil, "Invalid update. Cannot resolve actor for detaching security configuration." unless enable_actor

            delegated_bypass.enable(actor: enable_actor)
            source.repository_security_configuration&.remove_if_possible(
              action: "enabled",
              feature: :token_scanning_delegated_bypass,
              owner: T.must(source.owner),
            )
          end
          request.repository_id = source.id
        else
          return nil, "Invalid source. Repository or Organization expected."
        end
        response = GitHub::TokenScanning::Service::Client.new(actor).update_bypassers_for_source(request)

        return nil, "An error has occurred while attempting to update the bypass reviewers." if response.nil?
        return nil, response.error&.msg if response.error.present?
        return nil, "Failed to update bypass reviewers." if response.data.nil? || response.data.bypassers.nil?

        payload = { actor:, security_configuration_id:, bypass_reviewers: bypassers, bulk_update: true }
        if source.is_a?(Organization)
          payload[:org] = Organization.find_by(id: source.id)
          event_name = "org_secret_scanning_push_protection_bypass_list.add"
        else
          payload[:repo] = Repositories.domain.by_id(source.id)
          event_name = "repository_secret_scanning_push_protection_bypass_list.add"
        end
        GitHub.instrument(event_name, payload)

        [response.data.bypassers.map { |bypasser| SecretScanning::Models::Bypasser.from_proto_bypasser(bypasser) }, nil]
      end

      sig do
        params(
          source: T.any(Repository, Organization),
          security_configuration_id: T.nilable(Integer),
          actor: T.any(User, String, Integer),
        ).returns(T.nilable(String))
      end
      def self.remove_bypassers_for_source(source, security_configuration_id, actor)
        request = GitHub::Proto::SecretScanning::Bypassers::V1::RemoveBypassersForSourceRequest.new(security_configuration_id:)
        if source.is_a?(Organization)
          request.organization_id = source.id
        elsif source.is_a?(Repository)
          delegated_bypass = SecretScanning::Features::Repo::DelegatedBypass.new(source)
          if delegated_bypass.enforced_enabled_by_security_configuration?
            return "Invalid deletion. Cannot remove repository bypass reviewers when delegated bypass is enabled by organization or security configuration."
          end
          if delegated_bypass.enabled_by_security_configuration?
            enable_actor = actor.is_a?(User) ? actor : User.find_by(id: actor)
            return "Invalid deletion. Cannot resolve actor for detaching security configuration." unless enable_actor

            delegated_bypass.enable(actor: enable_actor)
            source.repository_security_configuration&.remove_if_possible(
              action: "enabled",
              feature: :token_scanning_delegated_bypass,
              owner: T.must(source.owner),
            )
          end
          request.repository_id = source.id
        else
          return "Invalid source. Repository or Organization expected."
        end
        response = GitHub::TokenScanning::Service::Client.new(actor).remove_bypassers_for_source(request)
        return "An error has occurred while attempting to delete the bypass reviewers for this source." if response.nil?
        return response.error&.msg if response.error.present?

        payload = { actor:, security_configuration_id:, bulk_update: true }
        if source.is_a?(Organization)
          payload[:org] = Organization.find_by(id: source.id)
          event_name = "org_secret_scanning_push_protection_bypass_list.remove"
        else
          payload[:repo] = Repositories.domain.by_id(source.id)
          event_name = "repository_secret_scanning_push_protection_bypass_list.remove"
        end
        GitHub.instrument(event_name, payload)

        nil
      end

      sig do
        params(
          bypass_reviewers: T::Array[SecretScanning::Models::Bypasser],
          reviewers_source: T.any(Repository, Organization, Business),
        ).returns(
          SecretScanning::Models::BypasserIdsByType
        )
      end
      def self.split_bypasser_ids_by_type(bypass_reviewers, reviewers_source)
        user_ids = []
        role_ids = []
        team_ids = []
        business_team_ids = []
        enterprise_role_ids = []
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
          case GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType.resolve(T.cast(reviewer.reviewer_type, Symbol))
          when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::TEAM
            team_ids.push(reviewer.reviewer_id)
          when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ROLE
            role_ids.push(reviewer.reviewer_id)
          when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ORG_ADMIN
            # We're going to have to revisit this logic for the org-level experience!!
            unless org_owner.nil?
              user_ids.concat(org_owner.admin_ids)
            end
          when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ENTERPRISE_OWNER
            user_ids.concat(enterprise_owners.map(&:id))
          when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::BUSINESS_TEAM
            business_team_ids.push(reviewer.reviewer_id)
          when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ENTERPRISE_ROLE
            enterprise_role_ids.push(reviewer.reviewer_id)
          else
            # Shouldn't get here
          end
        end

        SecretScanning::Models::BypasserIdsByType.new(
          user_ids: user_ids,
          team_ids: team_ids,
          business_team_ids: business_team_ids,
          role_ids: role_ids,
          enterprise_role_ids: enterprise_role_ids
        )
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
        return [[], []] if role_ids.empty?
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
          actor: User).returns([
            T.nilable(SecretScanning::Models::BypasserUsersTeams),
            T.nilable(String),
          ])
      end
      def self.get_bypasser_users_teams(repository, actor)
        bypass_reviewers, error_message = get_bypassers(repository, actor)

        if error_message
          Failbot.report(SecretScanning::Errors::Error.new(error_message), app: FAILBOT_APP_NAME, repository: repository)
          return [nil, error_message]
        end

        bypass_reviewers ||= []

        reviewer_ids_by_type = split_bypasser_ids_by_type(bypass_reviewers, repository)
        org = repository.owner
        unless org.is_a?(Organization)
          # Delegated bypass is only supported for org-owned repositories
          Failbot.report(SecretScanning::Errors::Error.new("DelegatedBypassService: Repository owner is not an organization"), app: FAILBOT_APP_NAME, repository: repository)
          return [nil, "Repository owner is not an organization"]
        end
        business = org.business

        users = User.where(id: reviewer_ids_by_type.user_ids).to_a

        # Get users and teams assigned to regular roles
        role_users, teams = SecretScanning::Services::DelegatedBypassService.get_users_teams_from_role_ids(reviewer_ids_by_type.role_ids, repository)
        users.concat(role_users) if role_users.any?
        teams.concat(Team.where(id: reviewer_ids_by_type.team_ids).to_a) if reviewer_ids_by_type.team_ids.any?

        business_teams = BusinessTeam.where(id: reviewer_ids_by_type.business_team_ids).to_a

        # Get users and business teams assigned to enterprise roles, that are visible by this org
        if business.present? && reviewer_ids_by_type.enterprise_role_ids.any?
          enterprise_role_users, enterprise_role_teams = SecretScanning::Util::Authorization.get_enterprise_role_assignees_visible_to_org(business, org, reviewer_ids_by_type.enterprise_role_ids)
          users.concat(enterprise_role_users)
          business_teams.concat(enterprise_role_teams)
        end

        # Add org admins and security managers
        users.concat(org.admins)
        users.concat(SecurityProduct::SecurityManagers.new(org).users)
        if business.present?
          users.concat(SecurityProduct::EnterpriseSecurityManagers.new(business).users)
        end

        [SecretScanning::Models::BypasserUsersTeams.new(users: users.uniq, teams: teams.uniq, business_teams: business_teams.uniq), nil]
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
      def self.is_valid_bypasser?(reviewer_id, reviewer_type, organization)
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
        when "INTEGRATION"
          return true if Integration.find_by(id: reviewer_id).present?
        when "BUSINESS_TEAM"
          return true if BusinessTeam.find_by(id: reviewer_id).present?
        when "ENTERPRISE_ROLE"
          return true if EnterpriseRole.find_by(id: reviewer_id).present?
        end
        false
      end

      # This method confirms whether the given user can review bypass requests for the given repository and why
      sig { params(repository: Repository, user: T.any(User, PublicKey)).returns([T::Boolean, String]) }
      def self.can_review_bypass_request?(repository, user)
        return false, "requester is a Public Key, not a User" if user.is_a?(PublicKey)

        org = repository.owner
        # We only support delegated bypass for org-owned repos
        return false, "repository is not org-owned" unless org.present? && org.is_a?(Organization)

        org_delegated_bypass = SecretScanning::Features::Org::DelegatedBypass.new(org)
        repo_delegated_bypass = SecretScanning::Features::Repo::DelegatedBypass.new(repository)

        bypass_reviewers, error_message = self.get_bypassers(repository, user.id)
        if bypass_reviewers.nil? || error_message
          Failbot.report(SecretScanning::Errors::Error.new("Could not get bypass reviewers for repo"), app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: user.id)
          return false, "could not get bypass reviewers for repo"
        end

        integration_bypass_reviewers, other_bypass_reviewers = bypass_reviewers.partition do |reviewer|
          GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType.resolve(T.cast(reviewer.reviewer_type, Symbol)) == GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::INTEGRATION
        end

        if user.can_have_granular_permissions?
          # Programmatic actors (apps) can review bypass requests if they have write access to the FGR
          org_fgr_write_access = org.resources.organization_secret_scanning_bypass_requests.writable_by?(user)
          repo_fgr_write_access = repository.resources.secret_scanning_bypass_requests.writable_by?(user)
          if org_fgr_write_access
            return true, "user has org review delegated bypass FGR write access"
          elsif repo_fgr_write_access
            return true, "user has repo review delegated bypass FGR write access"
          end
          # If this programmatic actor doesn't have FGR access, see if they are listed as an integration bypass reviewer
          integration_bypass_reviewers = integration_bypass_reviewers.each do |integration_reviewer|
            integration = Integration.find_by(id: integration_reviewer.reviewer_id)
            if integration.nil?
              GitHub.logger.info("Could not find integration for secret scanning bypass reviewer", "repo.id": repository.id, "user.id": user.id, "integration.id": integration_reviewer.reviewer_id, "code.function": __method__)
              next
            end
            bot = integration.bot
            return true, "user is the bot for integration: #{integration.name}" if user == bot
          end
          # If we got here, this programmatic actor has neither FGR access nor does it match any integration bypass reviewers
          return false, "user is not an integration bypass reviewer and has neither org nor repo review delegated bypass FGR write access"
        end

        return true, "user has repo delegated bypass FGP" if repository.has_repo_delegated_bypass_fgp?(user)

        return true, "user has org delegated bypass FGP" if repository.has_org_delegated_bypass_fgp?(user)

        other_bypass_reviewers.each do |bypasser|
          # bypassers with :EXEMPT mode should not be able to review bypass requests
          if self.bypasser_has_exempt_mode?(bypasser)
            next
          end

          can_review, reason = self.user_is_bypasser?(user, bypasser, repository)
          return true, reason if can_review
        end
        [false, "user is not a bypass reviewer"]
      end

      sig { params(bypasser: SecretScanning::Models::Bypasser).returns(T::Boolean) }
      def self.bypasser_has_exempt_mode?(bypasser)
        mode = bypasser.mode
        mode_int = if mode.is_a?(Integer)
          mode
        elsif mode.is_a?(Symbol)
          GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserMode.resolve(mode)
        else
          nil
        end
        return false if mode_int.nil?
        mode_int == GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserMode::EXEMPT
      end

      sig { params(user: User, bypasser: SecretScanning::Models::Bypasser, repository: Repository).returns([T::Boolean, String]) }
      def self.user_is_bypasser?(user, bypasser, repository)
        case GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType.resolve(T.cast(bypasser.reviewer_type, Symbol))
        when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::TEAM
          team = Team.find_by(id: bypasser.reviewer_id)
          if team.nil?
            GitHub.logger.info("Could not find team for secret scanning bypass reviewer", "repo.id": repository.id, "user.id": user.id, "team.id": bypasser.reviewer_id, "code.function": __method__)
            return false, "Could not find team for secret scanning bypass reviewer"
          end
          return true, "user is member of team: #{team.name}" if team.members.include?(user)
        when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ROLE
          role = Role.find_by(id: bypasser.reviewer_id)
          if role.nil?
            GitHub.logger.info("Could not find role for secret scanning bypass reviewer", "repo.id": repository.id, "user.id": user.id, "role.id": bypasser.reviewer_id, "code.function": __method__)
            return false, "Could not find role for secret scanning bypass reviewer"
          end
          default_role = Team::ABILITIES_TO_PERMISSIONS.has_key?(role.name)
          if default_role
            # This is a default role, so check the repo permissions hash
            permissions = repository.permissions_hash_for(actor: user)
            return true, "user has default role: #{role.name}" if permissions.fetch(Team::ABILITIES_TO_PERMISSIONS[role.name].to_sym, nil)
          else
            # We know by this point that the role is a custom role
            repo_role = T.cast(role, RepositoryRole)
            can_review, reason = SecretScanning::Util::Authorization.user_has_custom_role_directly_or_via_team?(user, repo_role, repository)
            return can_review, reason if can_review
          end
        when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ORG_ADMIN
          org_owner = repository.owner
          return false, "repo owner should be an org" if !org_owner.nil? && !org_owner.is_a?(Organization)
          return true, "user is an org owner" if !org_owner.nil? && org_owner.adminable_by?(user)
        when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ENTERPRISE_OWNER
          return true, "user is a business owner" if repository.business&.owner?(user)
        when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::BUSINESS_TEAM
          business_team = BusinessTeam.find_by(id: bypasser.reviewer_id, business: repository.business)
          if business_team.nil?
            GitHub.logger.info("Could not find business team for secret scanning bypass reviewer", "repo.id": repository.id, "user.id": user.id, "business_team.id": bypasser.reviewer_id, "code.function": __method__)
            return false, "Could not find business team for secret scanning bypass reviewer"
          end
          # First ensure that the team has access to the current organization
          org = repository.owner
          return false, "repository owner is not an organization" unless org.present? && org.is_a?(Organization)
          return false, "business team is not associated with the organization" unless business_team.is_associated_with_organization?(org)
          # Then check the user's membership status
          return true, "user is member of business team: #{business_team.name}" if business_team.member?(user)
        when GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ENTERPRISE_ROLE
          enterprise_role = EnterpriseRole.find_by(id: bypasser.reviewer_id)
          if enterprise_role.nil?
            GitHub.logger.info("Could not find enterprise role for secret scanning bypass reviewer", "repo.id": repository.id, "user.id": user.id, "enterprise_role.id": bypasser.reviewer_id, "code.function": __method__)
            return false, "Could not find enterprise role for secret scanning bypass reviewer"
          end
          org = repository.owner
          return false, "repository owner is not an organization" unless org.present? && org.is_a?(Organization)
          can_review, reason = SecretScanning::Util::Authorization.user_has_enterprise_role_directly_or_via_team?(user, enterprise_role, org)
          return can_review, reason if can_review
        else
          # Shouldn't get here
          Failbot.report(
            SecretScanning::Errors::Error.new("Unknown bypass reviewer type"),
            app: FAILBOT_APP_NAME,
            repository_id: repository.id,
            user_id: user.id,
            reviewer_type: bypasser.reviewer_type,
          )
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
      def self.suggested_bypassers(source, current_user, params)
        enterprise_apps_only = source.is_a?(Business)
        suggestions = RulesEngine::Suggestions.bypass_actors_for(
          source,
          current_user,
          query: params[:q].blank? ? nil : params[:q],
          exclude_integrations: false,
          enterprise_apps_only: enterprise_apps_only
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
        delegated_bypass_business = SecretScanning::Features::Business::DelegatedBypass.new(business) if business.present?

        if grouped[:EnterpriseOwner].present?
          if delegated_bypass_business&.enabled_for_security_configuration?
            result.concat(T.must(grouped[:EnterpriseOwner]))
          end
        end

        if grouped[:OrganizationAdmin].present?
          org_admin = T.must(grouped[:OrganizationAdmin])
          org_admin = org_admin.each { |admin| admin[:actorId] = 1 }
          result.concat(org_admin)
        end

        if grouped[:BusinessTeam].present? && delegated_bypass_business&.enabled_for_security_configuration?
          result.concat(T.must(grouped[:BusinessTeam]))
        end

        if grouped[:EnterpriseRole].present? && delegated_bypass_business&.enabled_for_security_configuration?
          result.concat(T.must(grouped[:EnterpriseRole]))
        end

        if grouped[:Integration].present? && delegated_bypass_business&.enabled_for_security_configuration?
          result.concat(T.must(grouped[:Integration]))
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

        # If the bypasser list is empty, revert to the regular bypass flow
        bypassers, err = get_bypassers(repository, actor)

        # If there's a problem with getting bypassers from TSS, assume that the user is not a bypasser
        # and thus needs the delegated bypass flow. This is a conservative approach to prevent non-privileged users
        # from self-approving. If the user is in fact a bypasser, they can always try their push again.
        return true unless err.nil?

        return false if bypassers.nil?
        true
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
      def self.get_bypasser_type_from_actor_type(actor_type)
        case actor_type
        when "Team"
          proto_value = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::TEAM
        when "RepositoryRole"
          proto_value = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ROLE
        when "OrganizationAdmin"
          proto_value = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ORG_ADMIN
        when "BusinessTeam"
          proto_value = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::BUSINESS_TEAM
        when "EnterpriseOwner"
          proto_value = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ENTERPRISE_OWNER
        when "EnterpriseRole"
          proto_value = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::ENTERPRISE_ROLE
        when "Integration"
          proto_value = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::INTEGRATION
        else
          proto_value = GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType::UNKNOWN
        end
        T.must(GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserType.lookup(proto_value))
      end

      sig { params(reviewer: SecretScanning::Models::Bypasser).returns(T::Hash[Symbol, T.untyped]) }
      def self.security_config_bypass_actor_hash(reviewer)
        # convert mode to integer
        reviewer_mode = reviewer.mode
        mode_int = if reviewer_mode.is_a?(Symbol)
          GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserMode.resolve(reviewer_mode) || GitHub::Proto::SecretScanning::Bypassers::V1::Bypasser::BypasserMode::ALWAYS
        else
          reviewer_mode
        end

        ret = {
          id: reviewer.id,
          actorId: reviewer.reviewer_id,
          bypassMode: mode_int,
          # These fields are used by the UI
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
          business_team = BusinessTeam.find_by(id: reviewer.reviewer_id)
          if business_team
            ret[:name] = business_team.name || ""
          end
          ret[:actorType] = "BusinessTeam"
        when :ENTERPRISE_OWNER
          ret[:name] = "Enterprise owners"
          ret[:actorType] = "EnterpriseOwner"
        when :ENTERPRISE_ROLE
          enterprise_role = EnterpriseRole.find_by(id: reviewer.reviewer_id)
          if enterprise_role
            ret[:name] = enterprise_role.display_name
          end
          ret[:actorType] = "EnterpriseRole"
        when :INTEGRATION
          integration = Integration.find_by(id: reviewer.reviewer_id)
          if integration
            ret[:name] = integration.name || ""
            ret[:actorType] = "Integration"
            ret[:preferredAvatarUrl] = integration.preferred_avatar_url
          end
        else
          {}
        end
        ret
      end

      sig { params(reviewer: SecretScanning::Models::Bypasser).returns(T::Hash[Symbol, T.untyped]) }
      def self.ui_bypasser_hash(reviewer)
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
          business_team = BusinessTeam.find_by(id: reviewer.reviewer_id)
          if business_team
            display_reviewer[:name] = business_team.name || ""
            display_reviewer[:preferred_avatar_url] = business_team.primary_avatar_url
            display_reviewer[:reviewer_type] = :"Enterprise team"
          end
        when :ENTERPRISE_OWNER
          display_reviewer[:name] = "Enterprise owners"
          display_reviewer[:reviewer_type] = :ROLE
        when :ENTERPRISE_ROLE
          enterprise_role = EnterpriseRole.find_by(id: reviewer.reviewer_id)
          if enterprise_role
            display_reviewer[:name] = enterprise_role.display_name
            display_reviewer[:reviewer_type] = :"Enterprise role"
          end
        when :INTEGRATION
          integration = Integration.find_by(id: reviewer.reviewer_id)
          if integration
            display_reviewer[:name] = integration.name || ""
            display_reviewer[:reviewer_type] = :"INTEGRATION"
            display_reviewer[:preferred_avatar_url] = integration.primary_avatar_url
          end
        end
        display_reviewer
      end
    end
  end
end
