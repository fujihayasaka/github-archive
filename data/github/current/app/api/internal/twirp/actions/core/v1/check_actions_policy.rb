# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class CheckActionsPolicy
        include GitHub::Memoizer

        attr_reader :repo, :allowed_actions, :disallowed_actions

        MAX_DISALLOWED_ACTIONS_TO_DISPLAY = 5

        def self.call(request)
          new(request).call
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        def initialize(request)
          database_id = Platform::Helpers::NodeIdentification.from_global_id(request.repository_id.global_id).last

          @repo = Repositories::Public.find_active!(database_id)
          @allowed_actions = []
          @local_only_actions = []
          @disallowed_actions = request.actions.uniq.map { |action| Action.new(action) }
          @include_local_only_actions = request.include_local_only_actions

          # policy_checkable_entity is the entity where the policy check
          # should be performed. It can either be an org or a repo.
          # We want to ignore repo level policies and always depend on org
          # policies in case of required workflows. If actions is disabled on the org,
          # we want to check enterprise policies.
          @policy_checkable_entity = if request.should_ignore_repo_policies && repo.owner.business.present? && repo.owner.actions_disabled?
            repo.owner.business
          elsif request.should_ignore_repo_policies
            repo.owner
          else
            repo
          end
        end

        def call
          return success_response if allows_all_actions?
          # When include_local_only_actions is set, we want to remove local actions from the list last
          # This allows us to know which actions are only allowed due to the local policy
          unless @include_local_only_actions
            # Always enabled
            allow_local_actions!
            allow_local_to_enterprise_actions! if allows_local_to_enterprise_actions?
          end

          unless @policy_checkable_entity.allows_local_actions_only? || @policy_checkable_entity.owner_allows_local_actions_only?
            allow_github_owned_actions! if allows_github_owned_actions?
            allow_pattern_matching_actions! if allows_specific_actions_patterns?
            allow_verified_actions! if allows_verified_actions?

            # must happen last as it may negate any of the previous policies
            block_pattern_matching_actions! if allows_specific_actions_patterns? && actions_blocklist_enabled?
          end

          if @include_local_only_actions
            local_to_repo_actions = allow_local_actions!
            local_to_enterprise_actions = allow_local_to_enterprise_actions! if allows_local_to_enterprise_actions?

            @local_only_actions = [local_to_repo_actions, local_to_enterprise_actions].compact.reduce([], :|)
          end

          return error_response if disallowed_actions.any?
          success_response
        end

        private

        def allows_github_owned_actions?
          @policy_checkable_entity.allows_github_owned_actions?
        end

        def allows_specific_actions_patterns?
          @policy_checkable_entity.can_use_actions_allowlist? && @policy_checkable_entity.allows_specific_actions_patterns?
        end

        def allows_verified_actions?
          @policy_checkable_entity.allows_verified_actions?
        end

        def allows_all_actions?
          @policy_checkable_entity.allows_all_actions?
        end

        # Local to the repo via directory path. Or has the same owner as this repo.
        def allow_local_actions!
          return unless disallowed_actions.any?

          local_to_repo = disallowed_actions.select do |action|
            action.local_to_repo? || action.owner_login == repo.owner.display_login.downcase
          end

          @disallowed_actions = disallowed_actions - local_to_repo
          @allowed_actions = allowed_actions + local_to_repo

          local_to_repo
        end

        # Actions that belong to any org within an Enterprise are allowed
        def allow_local_to_enterprise_actions!
          return unless disallowed_actions.any?

          org_logins = repo.owner.business.organizations.pluck(:display_login).map(&:downcase)

          local_to_enterprise = disallowed_actions.select do |action|
            org_logins.include? action.owner_login
          end

          @disallowed_actions = disallowed_actions - local_to_enterprise
          @allowed_actions = allowed_actions + local_to_enterprise

          local_to_enterprise
        end

        def allow_pattern_matching_actions!
          return unless disallowed_actions.any?

          allowed_patterns = if actions_blocklist_enabled?
            @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.allowed
          else
            @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns
          end
          allowed_regex = Regexp.union(allowed_patterns.map(&:regex))

          allowed_by_pattern = disallowed_actions.select do |action|
            action.uses_string.match? allowed_regex
          end

          @disallowed_actions = disallowed_actions - allowed_by_pattern
          @allowed_actions = allowed_actions + allowed_by_pattern
        end

        def block_pattern_matching_actions!
          return unless allowed_actions.any?

          blocked_patterns = @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.blocked
          blocked_regex = Regexp.union(blocked_patterns.map { |p| p.regex(trim_blocked_prefix: true) })

          blocked_by_pattern = allowed_actions.select do |action|
            action.uses_string.match? blocked_regex
          end

          @disallowed_actions = disallowed_actions + blocked_by_pattern
          @allowed_actions = allowed_actions - blocked_by_pattern
        end

        def allow_github_owned_actions!
          return unless disallowed_actions.any?

          github_owned = disallowed_actions.select do |action|
            action.github_owned?
          end

          @disallowed_actions = disallowed_actions - github_owned
          @allowed_actions = allowed_actions + github_owned
        end

        def allow_verified_actions!
          return unless disallowed_actions.any?

          owner_logins = disallowed_actions.map(&:owner_login)
          owner_logins.compact!

          return unless owner_logins.any?

          verified_orgs = []

          if GitHub.dotcom_connection_enabled?
            verified_orgs = fetch_dotcom_verified_orgs(owner_logins) || []
          else
            orgs = Organization.select(:id, :display_login).where(login: owner_logins)
            verified_org_ids = Configurable::RepositoryActionVerifiedOrg.filter_verified_org_ids(orgs.pluck(:id)).to_set
            verified_orgs = orgs.select { |org| verified_org_ids.include?(org.id) }.map { |org| org.display_login.downcase }
          end

          verified_actions = disallowed_actions.select do |action|
            verified_orgs.include? action.owner_login
          end

          @disallowed_actions = disallowed_actions - verified_actions
          @allowed_actions = allowed_actions + verified_actions
        end

        def allows_local_to_enterprise_actions?
          repo.owner.business.present?
        end

        # Allow internal actions in GHEC/GHES
        def internal_actions_allowed?
          return false unless !repo.public? && repo.owner.business.present?
          true
        end

        # Allow private actions in GHEC/GHES/Dotcom
        def private_actions_allowed?
          repo.private? && !repo.internal?
        end

        def error_response
          rules = []

          if allows_local_to_enterprise_actions?
            rules << "within a repository that belongs to your Enterprise account"
          else
            rules << "within a repository owned by #{repo.owner.display_login}"
          end

          if allows_github_owned_actions?
            rules << "created by GitHub"
          end

          if allows_verified_actions?
            rules << "verified in the GitHub Marketplace"
          end

          if allows_specific_actions_patterns?
            rules << "matching the following: " + @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.pluck(:value).sort.join(", ")
          end

          error_message = "#{disallowed_actions_to_sentence} #{"is".pluralize(disallowed_actions.count)} not allowed to be used in #{repo.name_with_display_owner}."
          error_message = error_message + " Actions in this workflow must be: #{rules.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")}."

          if @dotcom_connection_error_message
            error_message = @dotcom_connection_error_message
          end

          {
            is_execution_allowed: false,
            error_message: error_message.truncate(1_000),
            local_only_actions: @local_only_actions.map(&:to_s),
            are_internal_actions_allowed: internal_actions_allowed?,
            are_private_actions_allowed: private_actions_allowed?,
          }
        end

        def disallowed_actions_to_sentence
          return disallowed_actions.to_sentence if disallowed_actions.count <= MAX_DISALLOWED_ACTIONS_TO_DISPLAY

          not_displayed_actions_count = disallowed_actions.count - MAX_DISALLOWED_ACTIONS_TO_DISPLAY
          disallowed_actions.first(MAX_DISALLOWED_ACTIONS_TO_DISPLAY).to_sentence(last_word_connector: ", ") + ", and #{not_displayed_actions_count} other #{"action".pluralize(not_displayed_actions_count)}"
        end

        def success_response
          {
            is_execution_allowed: true,
            error_message: nil,
            local_only_actions: @local_only_actions.map(&:to_s),
            are_internal_actions_allowed: internal_actions_allowed?,
            are_private_actions_allowed: private_actions_allowed?,
          }
        end

        def fetch_dotcom_verified_orgs(owner_logins)
          return [] unless dotcom_connected? && GitHub.dotcom_download_actions_archive_enabled?

          begin
            response = GitHub::Connect.fetch_dotcom_actions_verified_owners(owner_logins)
            response["verified_logins"]
          rescue GitHub::Connect::ApiError
            # set dotcom connection error message
            disallowed_actions_message = "#{disallowed_actions_to_sentence} #{"is".pluralize(disallowed_actions.count)}"
            @dotcom_connection_error_message = "An internal server error occurred while attempting to check if #{disallowed_actions_message} verified in the GitHub Marketplace. Try again or contact your enterprise administrator."
            nil
          end
        end

        def dotcom_connected?
          GitHub::Connect.dotcom_connection.check_status == :connected
        end

        memoize def actions_blocklist_enabled?
          @policy_checkable_entity.feature_enabled?(:actions_blocklist)
        end

        class Action
          attr_reader :uses_string

          GITHUB_OWNED_LOGINS = %w{actions github}

          def initialize(uses_string)
            @uses_string = uses_string.downcase
          end

          def github_owned?
            return false unless owner_login
            GITHUB_OWNED_LOGINS.include? owner_login
          end

          def owner_login
            return @owner_login if defined?(@owner_login)

            parts = uses_string.split("/")
            owner = parts[0]

            @owner_login = owner.downcase if owner.match? User::LOGIN_REGEX
          end

          def local_to_repo?
            # A local Action in the repo will look like this: ./path/to/dir
            uses_string.starts_with? "./"
          end

          def to_s
            uses_string
          end
        end
      end
    end
  end
end
