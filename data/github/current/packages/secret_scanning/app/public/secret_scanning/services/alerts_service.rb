# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Services
    class AlertsService
      extend T::Sig

      include SecretScanning::Features::FeatureFlagHelper
      include SecretScanning::Errors
      include SecretScanning::Constants
      include ::CopilotChatHelper

      LOCATIONS_PER_PAGE = 3
      ERROR_TYPE = "AlertsServiceError"

      sig { params(repository: Repository, user: User, id: Integer, page: T.nilable(Integer)).returns([T.nilable(GitHub::TokenScanning::Service::Token), T.nilable(String)]) }
      def get_alert(repository, user, id, page)
        response = GitHub::TokenScanning::Service::Client.new(user).get_token(
          repository_id: repository.id,
          token_id: id.to_i,
          include_commit_oids: true,
          include_included_locations: true,
          limit: LOCATIONS_PER_PAGE,
          page: page || 1,
          feature_flags: get_tokens_api_feature_flags(repository),
          include_location_count: true,
          include_config_filters: true,
        )

        if response.nil? || response.error.present? || response.data.nil? || response.data&.token.nil?
          err_msg = response&.error&.msg || "An error has occurred while fetching the alert"
          Failbot.report(SecretScanning::Errors::ServiceError.new(err_msg), app: FAILBOT_APP_NAME, alert_id: id, repository_id: repository.id, user_id: user.id)
          return nil, err_msg
        end

        [GitHub::TokenScanning::Service::Client.wrap_token(T.must(response.data&.token), repository, response.data), nil]
      end

      sig { params(repository: Repository, user: User, numbers: T::Array[Integer], resolution: String, dismissal_comment: T.nilable(String), numbers_to_slugs: T::Hash[Integer, String]).returns(T.nilable(T.any(SecretScanning::Errors::ServiceError, UnprocessableEntity))) }
      def resolve_alert(repository:, user:, numbers:, resolution:, dismissal_comment: nil, numbers_to_slugs: {})
        dismissal_comment = normalize_dismissal_comment(dismissal_comment)
        service_resolution = GitHub::TokenScanning::Service::Client.to_resolution(resolution)
        if service_resolution == GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED
          dismissal_comment = nil
        end

        return UnprocessableEntity.new unless service_resolution.present?

        response = GitHub::TokenScanning::Service::Client.new(user).resolve_tokens(
          repository_id: repository.id,
          token_numbers: numbers,
          resolver_id: user.id,
          resolution: service_resolution,
          default_branch_name: repository.default_branch,
          feature_flags: [],
          resolution_comment: dismissal_comment,
        )

        if response.nil?
          return SecretScanning::Errors::ServiceError.new("timeout when resolving token")
        end

        if response.error.present?
          return SecretScanning::Errors::ServiceError.new(response.error.msg)
        end

        numbers.each do |number|
          log_audit_entry_for_resolution(user, repository, number.to_i, resolution, numbers_to_slugs[number] || "")
        end

        nil
      end

      sig { params(repository: Repository, user: User, number: Integer).returns(T.nilable(T.any(SecretScanning::Errors::ServiceError, UnprocessableEntity))) }
      def report_alert(repository:, user:, number:)
        response = GitHub::TokenScanning::Service::Client.new(user).report_token(
          repository_id: repository.id,
          number: number,
          reporting_user_id: user.id,
        )

        if response.nil?
          return SecretScanning::Errors::ServiceError.new("An error has occurred while reporting the alert")
        end

        if response.error.present?
          return SecretScanning::Errors::ServiceError.new(T.must(response.error).msg)
        end

        nil
      end

      sig { params(repository: Repository, user: User, result: GitHub::TokenScanning::Service::Token).returns(T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetTimelineResponse)) }
      def get_alert_timeline(repository, user, result)
        options = {}
        options[:repository_id] = repository.id
        options[:token_alert_number] = result.number
        response  = GitHub::TokenScanning::Service::Client.new(user).get_timeline(options)

        if response.nil? || response.error.present? || response.data.nil?
          err_msg = response&.error&.msg || "Failed to load timeline"
          Failbot.report(
            SecretScanning::Errors::ServiceError.new(err_msg),
            app: FAILBOT_APP_NAME,
            repository_id: options[:repository_id],
            token_alert_number: options[:token_alert_number])

          return
        end

        response.data
      end

      sig do
        params(
          activities: T::Array[SecretScanning::Models::Patv2Action],
          permissions: T::Array[SecretScanning::Models::Patv2Permissions],
          user: User
        ).returns(T.nilable(String))
      end
      def get_alert_activity_ai_audit(activities, permissions, user)
        options = {}
        options[:permissions_sets] = permissions.map do |permission|
          record = {}
          record[:target_type] = permission.target_type.to_s
          record[:target_name] = permission.target_name
          record[:permissions] = permission.scopes_hash
          record
        end
        options[:activities] = activities.map do |activity|
          add = {
            action: activity.action,
            request_method: activity.request_method,
            target: activity.target,
            target_type: activity.target_type
          }
          add
        end
        response = GitHub::TokenScanning::Service::Client.new(user).get_generated_alert_activity_audit(options)
        response&.data&.explanation
      end

      sig { params(repository: Repository, user: User, result: GitHub::TokenScanning::Service::Token).returns(T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetGeneratedAlertAutofixResponse)) }
      def get_generated_alert_autofix(repository, user, result)
        options = {}
        options[:repository_id] = repository.id
        options[:token_number] = result.number

        response = GitHub::TokenScanning::Service::Client.new(user).get_generated_alert_autofix(options)

        if response.nil? || response.error.present? || response.data.nil?
          # TODO: Report to failbot

          return
        end

        response.data
      end

      sig { params(repository: Repository, user: User).returns(T.nilable(String)) }
      def get_secure_storage_steps(repository, user)
        options = {}
        options[:repository_id] = repository.id

        prompt_prefix = "Examine the repo, and determine whether there are any best practices on storing raw secrets, and referencing them in the code. Based on your observations, suggest how the user should be storing this secret securely, and referencing it in the codebase. Do not provide code fragments. Use bullet points if you have multiple steps."

        GitHub.logger.with_named_tags(repo_id: repository.id, repo_nwo: repository.name_with_display_owner) do
          is_repo_indexed = ::SecurityCenter::AlertPrioritization::AlertPrioritizationHelper.is_repo_indexed_for_semantic_search(user: user, repo: repository)

          copilot_chat_res =
            if is_repo_indexed
              ask_copilot_chat_agent(prompt_prefix: prompt_prefix, repo: repository, user: user)
            else
              nil
            end

          if copilot_chat_res.nil?
            # TODO: Report to failbot
            return
          end

          GitHub.logger.info(
            "info.message" => "Received response from Copilot chat",
            "code.namespace" => self.class.name,
            "code.function" => "get_secure_storage_steps",
            "gh.copilot.response.response" => copilot_chat_res
          )

          copilot_chat_res
        end
      end

      sig { params(actor: T.untyped).returns(::SecurityCenter::AlertPrioritization::CopilotApiClient) }
      def copilot_api_client(actor:)
        ::SecurityCenter::AlertPrioritization::CopilotApiClient.new(
          hmac_secret: hmac_secret,
          integration_id: integration_id,
          token: copilot_mint_token(T.must(actor.most_recent_session)),
          user: actor
        )
      end

      def integration_id
        if Rails.env.development?
          return "ghas-secret-scanning-dev"
        end

        "ghas-secret-scanning"
      end

      sig { returns(String) }
      def hmac_secret
        if Rails.env.development?
          return GitHub.environment.fetch("COPILOT_ADVANCED_SECURITY_HMAC_KEY_DEV")
        end

        GitHub.environment.fetch("COPILOT_ADVANCED_SECURITY_HMAC_KEY")
      end

      # Sends a request to Copilot Chat.
      sig { params(prompt_prefix: String, repo: ::Repository, user: ::User).returns(String) }
      def ask_copilot_chat_agent(prompt_prefix:, repo:, user:)
        prompt = %{
          Repo name: "#{repo.name_with_display_owner}".
          #{prompt_prefix}
        }.squish

        copilot_api_client(actor: user).send_platform_agent_chat_message(prompt: prompt)
      end

      sig { params(repository: Repository, user: User, token_number: Integer).returns(T.nilable(SecretScanning::Models::OnDemandValidation)) }
      def validate_token_on_demand(repository, user, token_number)
        options = {}
        options[:repository_id] = repository.id
        options[:token_number] = token_number

        response = GitHub::TokenScanning::Service::Client.new(user).get_token_validation_status(
          repository_id: repository.id,
          token_number: token_number,
          requested_by_user_id: user.id
        )

        if response.nil? || response.error.present? || response.data.nil?
          Failbot.report(
            SecretScanning::Errors::ServiceError.new("Failed to validate token on demand"),
            app: FAILBOT_APP_NAME,
            repository_id: options[:repository_id],
            token_number: options[:token_number])

          return
        end

        validation_response = SecretScanning::Models::OnDemandValidation.new_verification_from_proto_validation_request(response.data)
        validation_response
      end

      private

      sig { params(comment: T.nilable(String)).returns(T.nilable(String)) }
      def normalize_dismissal_comment(comment)
        if comment.nil? || comment.empty?
          return nil
        end
        comment.encode("UTF-8", universal_newline: true)
      end

      sig { params(user: User, repo: Repository, id: Integer, resolution: String, slug: String).void }
      def log_audit_entry_for_resolution(user, repo, id, resolution, slug)
        payload = {
            user: user,
            repo: repo,
            number: id,
            secret_type: slug,
        }
        if repo.in_organization?
          payload[:org] = repo.organization
        end

        if resolution.to_sym == :reopened
          GitHub.instrument("secret_scanning_alert.reopen", payload)
        else
          payload[:resolution] = resolution.to_sym
          GitHub.instrument("secret_scanning_alert.resolve", payload)
        end
      end

      sig { override.returns(T.nilable(Copilot::User)) }
      def current_copilot_user; end

      sig { override.returns(T.nilable(User)) }
      def current_user; end
    end
  end
end
