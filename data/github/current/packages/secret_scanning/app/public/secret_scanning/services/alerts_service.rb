# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class AlertsService
      include SecretScanning::Features::FeatureFlagHelper
      include SecretScanning::Errors
      include SecretScanning::Constants
      include ::CopilotChatHelper
      include ::BlackbirdIndexHelper
      include GitHub::TokenScanning::SecretScanningHelper

      LOCATIONS_PER_PAGE = 3
      ERROR_TYPE = "AlertsServiceError"
      CAMPAIGNS_GET_TOKENS_MAX_PAGE_SIZE = 100

      sig do
        params(
          repository: Repository, user: User, id: Integer,
          page: T.nilable(Integer),
          include_related_alerts: T::Boolean,
        ).returns([T.nilable(GitHub::TokenScanning::Service::Token), T.nilable(SecretScanning::Errors::ServiceError)])
      end
      def get_alert(repository, user, id, page: nil, include_related_alerts: false)
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
          include_related_alerts: include_related_alerts,
        )

        if response.nil?
          service_error = SecretScanning::Errors::ServiceError.new("An unknown error has occurred while fetching the alert")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, alert_id: id, repository_id: repository.id, user_id: user.id)
          return nil, service_error
        end

        if response.error.present? || response.data.nil? || response.data&.token.nil?
          # if this is a 404, this is a valid case of alert not found and not a service error
          return nil, nil if response.error&.code == :not_found
          service_error = SecretScanning::Errors::ServiceError.new(response.error&.msg || "An error has occurred while fetching the alert")
          Failbot.report(service_error, app: FAILBOT_APP_NAME, alert_id: id, repository_id: repository.id, user_id: user.id)
          return nil, service_error
        end

        [GitHub::TokenScanning::Service::Client.wrap_token(T.must(response.data&.token), repository, response.data), nil]
      end

      sig { params(repository: Repository, user: User, numbers: T::Array[Integer], resolution: String, dismissal_comment: T.nilable(String), numbers_to_slugs: T::Hash[Integer, String]).returns(T.nilable(T.any(SecretScanning::Errors::ServiceError, UnprocessableEntity, NotFoundByService))) }
      def resolve_alert(repository:, user:, numbers:, resolution:, dismissal_comment: nil, numbers_to_slugs: {})
        dismissal_comment = normalize_dismissal_comment(dismissal_comment)
        service_resolution = GitHub::TokenScanning::Service::Client.to_resolution(resolution)

        return UnprocessableEntity.new unless service_resolution.present?

        response = GitHub::TokenScanning::Service::Client.new(user).resolve_tokens(
          repository_id: repository.id,
          owner_id: repository.owner_id,
          owner_type: repository.owner.is_a?(Organization) ? GitHub::Proto::SecretScanning::Api::V1::OwnerType::OWNER_TYPE_ORGANIZATION : GitHub::Proto::SecretScanning::Api::V1::OwnerType::OWNER_TYPE_USER,
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
          if response.error.code == :not_found
            return SecretScanning::Errors::NotFoundByService.new(response.error.msg)
          end
          return SecretScanning::Errors::ServiceError.new(response.error.msg)
        end

        numbers.each do |number|
          log_audit_entry_for_resolution(user, repository, number.to_i, resolution.to_sym, numbers_to_slugs[number] || "")
        end

        nil
      end

      sig { params(repository: Repository, user: User, number: Integer).returns(T.nilable(T.nilable(SecretScanning::Models::Reporting::ReportTokenResponse))) }
      def report_alert(repository:, user:, number:)
        response = GitHub::TokenScanning::Service::Client.new(user).report_token(
          repository_id: repository.id,
          number: number,
          reporting_user_id: user.id,
        )

        if response.nil? || response.data.nil? || response.error.present?
          repository_id = repository.id || 0
          Failbot.report(UnableToReportToken.new("failed to report token", repository_id, number), repo_id: repository_id)
          return nil
        end

        validation_details = SecretScanning::Models::OnDemandValidation.new_verification_from_proto_report_response(T.must(response.data))
        result = response.data&.result
        SecretScanning::Models::Reporting::ReportTokenResponse.new(validation: validation_details, result: T.must(result))
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

      sig { params(repository: Repository).returns(T::Boolean) }
      def is_repo_indexed_for_semantic_search?(repository:)
        return false unless cir = CopilotIndexedRepositories.find_by(repository: repository.id)
        cir.semantic_code_search_ok?
      end

      sig { returns(String) }
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

      sig { params(repository: Repository, user: User, token_number: Integer, closure_request_id: Integer).returns(T.nilable(StandardError)) }
      def update_token_with_closure_request_id(repository, user, token_number, closure_request_id)
        options = {
          repository_id: repository.id,
          token_number: token_number,
          closure_exemption_request_id: closure_request_id
        }
        response = GitHub::TokenScanning::Service::Client.new(user).update_token_with_closure_exemption_request_id(
          options
        )
        is_err, err = ServiceHelper.process_response(
          response: response,
          operation: "updating token with closure request ID",
          is_404_ok: false,
          failbot_attributes: {
            "gh.repo.id" => repository.id,
            "gh.user.id" => user.id,
            "gh.tss.alert.number" => token_number,
            "gh.tss.closure_exemption_request_id" => closure_request_id,
          }
        )
        return err if is_err

        nil
      end

      sig do
        params(
          repository: Repository,
          alert_number: Integer,
          assignee_ids: T::Array[Integer],
          assigned_by: User,
        ).returns(T.nilable(StandardError))
      end
      def set_alert_assignee(repository, alert_number, assignee_ids, assigned_by)
        assignee_id = assignee_ids.first

        request = GitHub::Proto::SecretScanning::Api::V2::SetAlertAssigneeRequest.new(
          repository_id: repository.id,
          alert_number:,
          assignee_id:,
          updated_by_id: assigned_by.id
        )
        response = GitHub::TokenScanning::Service::Client.new(assigned_by).set_alert_assignee(request)
        is_err, err = ServiceHelper.process_response(
          response:,
          operation: "setting alert assignee",
          is_404_ok: false,
          failbot_attributes: {
            "gh.repo.id" => repository.id,
            "gh.user.id" => assigned_by.id,
            "gh.tss.alert.number" => alert_number,
            "gh.tss.alert.assignee_ids" => assignee_ids,
          }
        )
        return err if is_err

        return if assignee_id.nil?
        return if assignee_id == assigned_by.id
        assignee = User.find_by(id: assignee_id) || return

        token, err = get_alert(repository, assigned_by, alert_number)
        return if token.nil? || err.present?

        if FeatureFlag.vexi.enabled?(:secret_scanning_use_notification_service_for_alert_assigned, default: false)
          notification_service = ::SecretScanning::NotificationService.new(caller_namespace: T.must(self.class.name))
          notification_service.deliver_alert_assigned(
            assignee:,
            owner: T.must(repository.owner),
            repo: repository,
            alert_number:,
            token_label: token.label,
            assigned_by:,
          )
        else
          # Don't send email only if the user has ignored the repository entirely
          return if Notifications::Subscriptions.repository_muted?(assignee, repository)

          SecretScanningMailer.user_assigned_to_alert(
            assignee:,
            owner: repository.owner,
            repo: repository,
            alert_number:,
            token_label: token.label,
            assigned_by:,
          ).deliver_later
        end
        nil
      end

      sig do
        params(
          repository: Repository,
          alert_number: Integer,
          validity: T.nilable(String),
          updated_by: User,
        ).returns(T.nilable(StandardError))
      end
      def set_alert_validity(repository, alert_number, validity, updated_by)
        request = GitHub::Proto::SecretScanning::Api::V2::SetAlertValidityRequest.new(
          repository_id: repository.id,
          alert_number:,
          validity: validity || "",
          updated_by_id: updated_by.id
        )
        response = GitHub::TokenScanning::Service::Client.new(updated_by).set_alert_validity(request)

        # Map expected precondition failures (e.g., non-custom-pattern alerts, clearing
        # automation-set validity) to user-facing service errors.
        if response&.error&.code == :failed_precondition
          return SecretScanning::Errors::ServiceError.new("Received error from TSS: #{T.must(T.must(response).error).msg}")
        end

        is_err, err = ServiceHelper.process_response(
          response:,
          operation: "setting alert validity",
          is_404_ok: false,
          failbot_attributes: {
            "gh.repo.id" => repository.id,
            "gh.user.id" => updated_by.id,
            "gh.tss.alert.number" => alert_number,
            "gh.tss.alert.validity" => validity.to_s,
          }
        )
        return err if is_err

        nil
      end

      sig { override.returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
      def current_copilot_user_v2; end

      sig { override.returns(T.nilable(User)) }
      def current_user; end

      sig do
        params(
          repository: Repository,
          user: User,
          alert_numbers: T::Array[Integer]
        ).returns(T::Array[GitHub::TokenScanning::Service::Token])
      end
      def self.fetch_secret_scanning_alerts_for_repo(repository:, user:, alert_numbers:)
        return [] if alert_numbers.empty?

        alert_numbers_set = T::Set[Integer].new(alert_numbers)

        default_tokens = fetch_secret_scanning_alerts_by_confidence(
          repository: repository,
          user: user,
          alert_numbers_set: alert_numbers_set,
          low_confidence: false
        )

        generic_tokens = fetch_secret_scanning_alerts_by_confidence(
          repository: repository,
          user: user,
          alert_numbers_set: alert_numbers_set,
          low_confidence: true
        )

        default_tokens + generic_tokens
      end

      sig do
        params(
          repository: Repository,
          user: User,
          alert_numbers_set: T::Set[Integer],
          low_confidence: T::Boolean
        ).returns(T::Array[GitHub::TokenScanning::Service::Token])
      end
      def self.fetch_secret_scanning_alerts_by_confidence(repository:, user:, alert_numbers_set:, low_confidence:)
        all_tokens = []
        next_cursor = T.let(nil, T.nilable(String))
        client = GitHub::TokenScanning::Service::Client.new(user)
        # Class-method form: the instance helper is unavailable in this `def self.` context.
        use_extended_timeout = SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled_in_hierarchy?(repository, FeatureFlags::GET_TOKENS_EXTENDED_TIMEOUT)

        loop do
          request_hash = {
            repo_selector: GitHub::Proto::SecretScanning::Api::V2::RepoSelector.new(
              repository_id: repository.id
            ),
            token_state: 0, # NO_STATE = fetch all alerts (open and resolved)
            limit: CAMPAIGNS_GET_TOKENS_MAX_PAGE_SIZE,
            low_confidence: low_confidence,
          }
          request_hash[:next_cursor] = next_cursor if next_cursor.present?

          request = GitHub::Proto::SecretScanning::Api::V2::GetTokensRequest.new(request_hash)
          request_options = request.to_h
          request_options[GitHub::TokenScanning::Service::Client::USE_EXTENDED_TIMEOUT_KEY] = true if use_extended_timeout
          response = client.get_tokens(request_options)
          raise ServiceError.new(response&.error&.msg || "No response when fetching alerts") if response.nil? || response.error.present?

          tokens = response.data.tokens
          all_tokens.concat(tokens.to_a)

          # Check for next cursor to break loop
          next_cursor = response.data.respond_to?(:next_cursor) ? response.data.next_cursor : nil
          break unless next_cursor.present?
        end

        # Filter to only the requested alert numbers
        all_tokens.filter_map do |token|
          GitHub::TokenScanning::Service::Client.wrap_token(token, repository) if alert_numbers_set.include?(token.number)
        end
      end

      private

      sig { params(comment: T.nilable(String)).returns(T.nilable(String)) }
      def normalize_dismissal_comment(comment)
        if comment.nil? || comment.empty?
          return nil
        end
        comment.encode("UTF-8", universal_newline: true)
      end
    end
  end
end
