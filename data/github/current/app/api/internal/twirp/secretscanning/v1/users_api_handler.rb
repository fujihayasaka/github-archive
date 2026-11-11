# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      # Provides access to User data.
      class UsersAPIHandler < SecretScanningAPIHandler
        include SecretScanning::Features::FeatureFlagHelper
        handles_service(GitHub::Proto::SecretScanning::Users::V1::UsersAPIService)

        allow_access_for :client

        FIND_USERS_HARD_LIMIT = 100

        exempt_from_tenant_context_requirement

        # Public: Implementation of the FindUsers Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::SecretScanning::Users::V1::FindUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of users, suitable for use in
        # a GitHub::Proto::SecretScanning::Users::V1::FindUsersResponse.
        def find_users(req, env)
          if req.business_selector.present?
            return get_users_by_business(req.business_selector.id, req.cursor)
          elsif req.ids.present?
            scope_or_error = get_users_by_id(req.ids, argument_name: "ids",
              limit: FIND_USERS_HARD_LIMIT)
          elsif req.ids_selector.present?
            scope_or_error = get_users_by_id(req.ids_selector.ids, argument_name: "selector.ids",
              limit: FIND_USERS_HARD_LIMIT)
          elsif req.logins_selector.present?
            scope_or_error = get_users_by_login(req.logins_selector.logins, argument_name: "selector.logins",
              limit: FIND_USERS_HARD_LIMIT)
          else
            return Twirp::Error.invalid_argument("invalid selector",
              argument: "selector")
          end

          if scope_or_error.is_a?(Twirp::Error)
            scope_or_error
          else
            {
              users: build_user_list(scope_or_error),
            }
          end
        end

        # Public: Implementation of the GetEnterprisesForUser Twirp RPC.
        #
        # Returns the list of enterprise IDs (Business#id) that a user is a member of.
        # Used for Public Monitoring Alerts to determine which enterprises should see alerts leaked by their users in public repos.
        #
        # req - The Twirp request as a GitHub::Proto::SecretScanning::Users::V1::GetEnterprisesForUserRequest.
        # _env - The Twirp environment as a Hash (required by Twirp but unused here).
        #
        # Returns the Twirp response data suitable for use in
        # a GitHub::Proto::SecretScanning::Users::V1::GetEnterprisesForUserResponse.
        sig { params(req: GitHub::Proto::SecretScanning::Users::V1::GetEnterprisesForUserRequest, _env: T.untyped).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error)) }
        def get_enterprises_for_user(req, _env)
          user_id = req.user_id

          if user_id == 0
            return Twirp::Error.invalid_argument("user_id must be present and non-zero", argument: "user_id")
          end

          user = User.find_by(id: user_id)

          if user.nil?
            GitHub.logger.info("user not found for enterprise lookup",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.user.id": user_id,
              enterprise_count: 0)
            return { enterprise_ids: [], enterprises: [] }
          end

          membership_method = GitHub::Proto::SecretScanning::PublicMonitoring::V1::AttributionMethod::ATTRIBUTION_METHOD_MEMBERSHIP
          domain_method = GitHub::Proto::SecretScanning::PublicMonitoring::V1::AttributionMethod::ATTRIBUTION_METHOD_VERIFIED_DOMAIN

          # Step 1: Membership enterprises (existing behavior via User::BusinessDependency)
          membership_enterprise_ids = user.business_ids.to_set

          # Step 2: Verified domain enterprises
          domain_enterprise_ids = enterprise_ids_from_verified_domains(user).to_set

          # Step 3: Merge — membership overrides domain
          attributions = {}
          membership_enterprise_ids.each { |eid| attributions[eid] = membership_method }
          domain_enterprise_ids.each { |eid| attributions[eid] ||= domain_method }

          enterprise_ids = attributions.keys
          enterprises = attributions.map do |eid, method|
            { enterprise_id: eid, attribution_method: method }
          end

          GitHub.logger.info("returning enterprises for user",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.user.id": user_id,
            enterprise_count: enterprise_ids.size,
            membership_count: membership_enterprise_ids.size,
            domain_count: domain_enterprise_ids.size)

          { enterprise_ids: enterprise_ids, enterprises: enterprises }
        end

        # Public: Implementation of the GetSecretAuthor Twirp RPC.
        #
        # Resolves the GitHub user ID and email for the author of a secret.
        # For commits, it looks up the user by author email.
        # For other content types (issues, PRs, discussions), it looks up the content author.
        # Returns user_id = 0 and user_email = "" if the author cannot be resolved.
        #
        # req - The Twirp request as a GitHub::Proto::SecretScanning::Users::V1::GetSecretAuthorRequest.
        # _env - The Twirp environment as a Hash (required by Twirp but unused here).
        #
        # Returns the Twirp response data suitable for use in
        # a GitHub::Proto::SecretScanning::Users::V1::GetSecretAuthorResponse.
        sig { params(req: GitHub::Proto::SecretScanning::Users::V1::GetSecretAuthorRequest, _env: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def get_secret_author(req, _env)
          repository_id = req.repository_id

          case req.content_source
          when :commit
            get_commit_author(T.must(req.commit), repository_id)
          when :content
            get_content_author(T.must(req.content), repository_id)
          else
            GitHub.logger.info("no content source provided",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.repo.id": repository_id,
              content_type: req.content_source,
              "gh.user.id": 0)
            { user_id: 0, user_email: "" }
          end
        end

        private

        # Private: Find enterprise IDs attributed to a user via their verified email domains.
        #
        # For each of the user's verified emails, extract the normalized domain, then find
        # VerifiableDomain records that are verified and match those domains. Map each
        # matching domain to its owning enterprise — either directly (owner_type "Business")
        # or indirectly via an org's parent business. Organization is STI-backed by User,
        # so org-owned domains are stored with owner_type "User".
        #
        # user - A User record.
        #
        # Returns an Array of Integer enterprise (Business) IDs.
        sig { params(user: User).returns(T::Array[Integer]) }
        def enterprise_ids_from_verified_domains(user)
          domains = user.emails.verified
            .where.not(normalized_domain: nil)
            .distinct
            .pluck(:normalized_domain)
          return [] if domains.empty?

          matching_owners = VerifiableDomain.verified.where(domain: domains).pluck(:owner_type, :owner_id)
          return [] if matching_owners.empty?

          enterprise_ids = Set.new
          org_owner_ids = []

          matching_owners.each do |owner_type, owner_id|
            case owner_type
            when "Business"
              enterprise_ids.add(owner_id)
            when "User"
              org_owner_ids << owner_id
            end
          end

          # Resolve org→business via association
          if org_owner_ids.any?
            Organization.where(id: org_owner_ids).includes(:business).each do |org|
              enterprise_ids.add(org.business.id) if org.business
            end
          end

          enterprise_ids.to_a
        end

        def get_users_by_business(business_id, cursor)
          next_cursor = nil
          last_processed_page = cursor.present? ? cursor.unpack("Q")[0] : 1

          biz = Business.find_by(id: business_id)
          unless biz.present?
            return Twirp::Error.invalid_argument("failed to fetch business", argument: "business_selector.id")
          end

          feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(biz)
          unless feature.feature_available_for_user_repositories?
            GitHub.logger.info("Attempted to list users for unsupported business", {
              "gh.business.id": business_id,
            })
            return { users: [], next_cursor: nil, }
          end

          user_scope = feature.list_enterprise_users_paged(page: last_processed_page, per_page: FIND_USERS_HARD_LIMIT)

          # If we got FIND_USERS_HARD_LIMIT users, there might be more, so we need to set a new cursor.
          if user_scope.length == FIND_USERS_HARD_LIMIT
            next_cursor = [last_processed_page + 1].pack("Q")
          end

          {
            users: build_user_list(user_scope),
            next_cursor: next_cursor,
          }
        end

        # Private: Returns Users for each of the given user IDs.
        #
        # ids - User IDs in a Google::Protobuf::RepeatedField
        #
        # Returns an ActiveRecord::Relation of User, or a Twirp::Error.
        def get_users_by_id(ids, argument_name:, limit:)
          if ids.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: argument_name)
          end

          if ids.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}",
              argument: argument_name)
          end

          # ids is a Google::Protobuf::RepeatedField, and we need to call #to_a to get a value
          # usable by ActiveRecord:
          User.where(id: ids.to_a)
        end

        # Private: Returns Users for each of the given user logins.
        #
        # logins - User logins in a Google::Protobuf::RepeatedField
        #
        # Returns an ActiveRecord::Relation of User, or a Twirp::Error.
        def get_users_by_login(logins, argument_name:, limit:)
          if logins.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: argument_name)
          end

          if logins.size > limit
            return Twirp::Error.invalid_argument("must have a length <= #{limit}",
              argument: argument_name)
          end

          # login is a Google::Protobuf::RepeatedField, and we need to call #to_a to get a value
          # usable by ActiveRecord:
          User.where(login: logins.to_a)
        end

        # Private: Convert an array of User objects to the shape Twirp responses expect.
        #
        # users - The array of User objects.
        #
        # Returns an array of Hash objects with user data that matches the
        # Twirp definition.
        def build_user_list(users)
          users.map do |user|
            {
              id: user.id,
              login: feature_flag_enabled_in_hierarchy?(user, FeatureFlags::USE_DISPLAY_LOGIN_TWIRP) ? user.display_login : user.login,
              name: user.safe_profile_name,
              email: user.email,
              type: user_type_enum(user),
            }
          end
        end

        # Private: Generate the UserType enum for a user.
        #
        # user - A User
        #
        # Returns a Symbol.
        def user_type_enum(user)
          case user
          when Organization
            :USER_TYPE_ORGANIZATION
          when Bot
            :USER_TYPE_BOT
          when Mannequin
            :USER_TYPE_MANNEQUIN
          when User
            :USER_TYPE_USER
          else
            :USER_TYPE_INVALID
          end
        end

        # Private: Resolve the author of a secret found in a commit by email lookup.
        #
        # commit_source - A GitHub::Proto::SecretScanning::Users::V1::CommitSource with commit_sha.
        # repository_id - The repository ID where the secret was detected.
        #
        # Returns a Hash with :user_id and :user_email.
        sig { params(commit_source: GitHub::Proto::SecretScanning::Users::V1::CommitSource, repository_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
        def get_commit_author(commit_source, repository_id)
          commit_sha = commit_source.commit_sha

          # Look up the repository first
          repository = Repository.find_by(id: repository_id)
          unless repository
            GitHub.logger.info("repository not found",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.repo.id": repository_id,
              "gh.commit.sha": commit_sha,
              "gh.user.id": 0)
            return { user_id: 0, user_email: "" }
          end

          # Look up the commit to get the author email.
          # Wiki commits live in the wiki's git repo, not the main repo.
          # Use find_wiki_commit (which delegates to unsullied_wiki) when is_wiki is set,
          # matching the pattern in ShowPayloadBuilder#serialize_location.
          author_email = begin
            commit = if commit_source.is_wiki
              repository.find_wiki_commit(commit_sha)
            else
              repository.find_commit(commit_sha)
            end
            commit&.author_email
          rescue GitRPC::ObjectMissing, GitRPC::InvalidObject => e
            GitHub.logger.info("commit object missing or invalid in git",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.repo.id": repository_id,
              "gh.commit.sha": commit_sha,
              "error.class": e.class.name)
            nil
          end

          if author_email.blank?
            GitHub.logger.info("commit not found or blank email",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.repo.id": repository_id,
              "gh.commit.sha": commit_sha,
              "gh.user.id": 0)
            return { user_id: 0, user_email: "" }
          end

          # Look up the repository's business for EMU shortcode handling
          business = repository.owner&.business

          # Use the existing find_by_email method which handles:
          # - Stealth/noreply emails (extracting user ID from the email pattern)
          # - Bot emails
          # - Regular verified emails via user_emails table
          user = User.find_by_email(author_email, business: business)

          unless user
            GitHub.logger.info("email not resolved to user",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.repo.id": repository_id,
              "gh.commit.sha": commit_sha,
              "gh.user.id": 0)
            return { user_id: 0, user_email: "" }
          end

          # For commit sources, return the commit author email (not necessarily the user's primary email).
          { user_id: user.id, user_email: author_email }
        end

        # Private: Get the author of a secret found in content (issues, PRs, discussions, etc.)
        #
        # content_source - A GitHub::Proto::SecretScanning::Users::V1::ContentSource with content_type, content_id.
        # repository_id - The repository ID where the secret was detected (used for logging).
        #
        # Returns a Hash with :user_id and :user_email.
        sig { params(content_source: GitHub::Proto::SecretScanning::Users::V1::ContentSource, repository_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
        def get_content_author(content_source, repository_id)
          content_type = content_source.content_type
          content_id = content_source.content_id

          expected_unresolvable_content_type = content_type.in?([
            :REPOSITORY_BLOB,
            :COMMIT_METADATA,
            :WIKI_BLOB,
            :CONTENT_TYPE_UNKNOWN,
          ])

          result = case content_type
          when :ISSUE_TITLE, :ISSUE_BODY
            get_author_by_id(Issue, content_id)
          when :ISSUE_COMMENT
            get_author_by_id(IssueComment, content_id)
          when :PULL_REQUEST_TITLE, :PULL_REQUEST_BODY
            get_pull_request_author(content_id)
          when :PULL_REQUEST_COMMENT, :PULL_REQUEST_TIMELINE_COMMENT
            # PR comments and timeline comments are stored as issue comments
            get_author_by_id(IssueComment, content_id)
          when :PULL_REQUEST_REVIEW_COMMENT
            get_author_by_id(PullRequestReviewComment, content_id)
          when :DISCUSSION_TITLE, :DISCUSSION_BODY
            get_author_by_id(Discussion, content_id)
          when :DISCUSSION_COMMENT
            get_author_by_id(DiscussionComment, content_id)
          when :COMMIT_COMMENT
            get_author_by_id(CommitComment, content_id)
          when :REPOSITORY_BLOB, :COMMIT_METADATA, :WIKI_BLOB, :CONTENT_TYPE_UNKNOWN
            # These content types represent file blobs or commit metadata, not user-created content.
            # They should be resolved via the commit path (with commit_sha), not content path.
            # Return 0 as there's no author to resolve via content_id.
            { user_id: 0, user_email: "" }
          else
            { user_id: 0, user_email: "" }
          end

          if result[:user_id] == 0 && !expected_unresolvable_content_type
            GitHub.logger.info("content author not found",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.repo.id": repository_id,
              content_type: content_type.to_s,
              content_id: content_id,
              "gh.user.id": 0)
          end

          result
        end

        # Private: Get the author of a pull request by the associated issue ID.
        # Note: The content_id for PRs is the Issue ID (not the PullRequest ID),
        # since PRs are associated with issues that share the same number.
        #
        # issue_id - The Issue ID associated with the pull request.
        #
        # Returns a Hash with :user_id and :user_email.
        sig { params(issue_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
        def get_pull_request_author(issue_id)
          return { user_id: 0, user_email: "" } if issue_id == 0

          issue = Issue.find_by(id: issue_id)
          return { user_id: 0, user_email: "" } unless issue&.pull_request?

          pull_request = issue.pull_request
          return { user_id: 0, user_email: "" } unless pull_request

          user = pull_request.user
          { user_id: user&.id || 0, user_email: user&.email || "" }
        end

        # Private: Generic helper to get author by finding a record by ID.
        #
        # model_class - The ActiveRecord model class to query.
        # record_id - The ID of the record to find.
        #
        # Returns a Hash with :user_id and :user_email.
        sig { params(model_class: T.class_of(ActiveRecord::Base), record_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
        def get_author_by_id(model_class, record_id)
          return { user_id: 0, user_email: "" } if record_id == 0

          record = model_class.find_by(id: record_id)
          return { user_id: 0, user_email: "" } unless record

          user_id = record.user_id
          return { user_id: 0, user_email: "" } if user_id.nil? || user_id == 0

          user = User.find_by(id: user_id)
          return { user_id: 0, user_email: "" } unless user

          { user_id: user_id, user_email: user.email || "" }
        end
      end
    end
  end
end
