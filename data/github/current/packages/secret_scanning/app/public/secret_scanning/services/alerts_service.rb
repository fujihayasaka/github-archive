# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Services
    class AlertsService
      include SecretScanning::Features::FeatureFlagHelper
      include SecretScanning::Errors
      include SecretScanning::Constants
      include ::CopilotChatHelper
      include ::BlackbirdIndexHelper
      include Commit::ReactDiffLinesHelper
      include GitHub::TokenScanning::SecretScanningHelper

      LOCATIONS_PER_PAGE = 3
      ERROR_TYPE = "AlertsServiceError"

      sig { params(repository: Repository, user: User, id: Integer, page: T.nilable(Integer), include_related_alerts: T::Boolean).returns([T.nilable(GitHub::TokenScanning::Service::Token), T.nilable(SecretScanning::Errors::ServiceError)]) }
      def get_alert(repository, user, id, page, include_related_alerts: false)
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

      sig { params(permissions: T.nilable(T.any(SecretScanning::Models::Permissions::Classic, SecretScanning::Models::Permissions::Fgp)), user: User).returns(T.nilable(String)) }
      def get_adversarial_audit(permissions, user)
        options = {}
        if permissions.is_a?(SecretScanning::Models::Permissions::Fgp)
          options[:pat_v2_permissions] = {}
          options[:pat_v2_permissions][:permissions] = permissions.permissions.map do |scope, permission|
            { scope: scope, permission: permission }
          end
        else
          options[:pat_v1_permissions] = {}
          options[:pat_v1_permissions][:scopes] = permissions&.all_scopes || []
        end

        response = GitHub::TokenScanning::Service::Client.new(user).get_adversarial_audit(options)

        if response.nil? || response.error.present? || response.data.nil?
          Failbot.report(
            SecretScanning::Errors::ServiceError.new("failed to generate adversarial audit"),
            app: FAILBOT_APP_NAME)

          return
        end

        response.data&.audit_response
      end

      sig do
        params(actions: T::Array[String], permissions: T.nilable(T.any(SecretScanning::Models::Permissions::Classic, SecretScanning::Models::Permissions::Fgp)), user: User)
        .returns([T.nilable(String), T.nilable(SecretScanning::Models::Permissions::PermissionsCollection)])
      end
      def get_permission_audit(actions, permissions, user)
        options = {
          audit_log_actions: actions
        }
        if permissions.is_a?(SecretScanning::Models::Permissions::Fgp)
          options[:pat_v2_permissions] = {}
          options[:pat_v2_permissions][:permissions] = permissions.permissions.map do |scope, permission|
            { scope: scope, permission: permission }
          end
        else
          options[:pat_v1_permissions] = {}
          options[:pat_v1_permissions][:scopes] = permissions&.all_scopes || []
        end

        response = GitHub::TokenScanning::Service::Client.new(user).get_permission_audit(options)

        if response.nil? || response.error.present? || response.data.nil?
          Failbot.report(
            SecretScanning::Errors::ServiceError.new("failed to generate permission scope reduction audit"),
            app: FAILBOT_APP_NAME)

          return nil, nil
        end

        unless permissions.present?
          return [response.data&.summary, nil]
        end

        removed_permissions = if permissions.is_a?(SecretScanning::Models::Permissions::Fgp)
          response.data&.removed_pat_v2_permissions
        else
          response.data&.removed_pat_v1_permissions
        end

        [response.data&.summary, mark_permissions_as_deleted(permissions.to_permissions_collection, removed_permissions)]
      end

      sig { params(token_type: String, actions: T::Array[String], user: User).returns(T.nilable(String)) }
      def get_workflow_audit(token_type, actions, user)
        options = {
          audit_log_actions: actions,
          token_type: token_type
        }
        response = GitHub::TokenScanning::Service::Client.new(user).get_workflow_audit(options)

        if response.nil? || response.error.present? || response.data.nil?
          Failbot.report(
            SecretScanning::Errors::ServiceError.new("failed to generate workflow audit"),
            app: FAILBOT_APP_NAME)

          return
        end

        response.data&.audit_response
      end

      sig { params(user: User, token_number: Integer, repository: Repository).returns(SecretScanning::Models::Autofix::AutofixSuggestionResponse) }
      def get_autofix_suggestion(user, token_number, repository)
        options = {}
        options[:repository_id] = repository.id
        options[:token_number] = token_number

        default_explanation = "Consider opening a pull request with a change that removes this token from your codebase."

        response = GitHub::TokenScanning::Service::Client.new(user).get_autofix_suggestion(options)
        if response.nil? || response.error.present? || response.data.nil?
          Failbot.report(
            SecretScanning::Errors::ServiceError.new("failed to generate autofix suggestion"),
            app: FAILBOT_APP_NAME)

          return SecretScanning::Models::Autofix::AutofixSuggestionResponse.new(diff_lines: [], explanation: default_explanation, accept_feedback: false)
        end

        encrypted_diff = T.must(response.data).encrypted_diff
        diff = SecretScanning::Encryption::EncryptedSecretsCryptoHelper.decrypt_encrypted_secret(encrypted_diff)
        explanation = T.must(response.data).explanation

        begin
          diff_with_only_one_new_line = diff.strip + "\n"
          parser = GitHub::Diff::Parser.new(diff_with_only_one_new_line)
          entries = []
          parser.each { |entry| entries << entry }
          entry = entries[0]
          highlighted_diff = SyntaxHighlightedDiff.new(repository)
          shd = highlighted_diff.colorized_lines(entry)
          if shd
            shd.each(&:freeze)
            shd.freeze
          end
          diff_lines = build_diff_line_data(entry, shd)
          response = SecretScanning::Models::Autofix::AutofixSuggestionResponse.new(diff_lines: diff_lines, explanation: explanation, accept_feedback: true)
          parse_success = true
        rescue => exception # rubocop:todo Lint/GenericRescue
          Failbot.report(SecretScanning::Errors::Error.new(exception), app: FAILBOT_APP_NAME, alert_number: token_number, repository_id: repository.id, user_id: T.must(user).id)
          parse_success = false
          response = SecretScanning::Models::Autofix::AutofixSuggestionResponse.new(diff_lines: [], explanation: default_explanation, accept_feedback: false)
        ensure
          GitHub.dogstats.increment("secret_scanning.alerts_service.get_autofix_suggestion.parsed", tags: ["success:#{parse_success}"])
        end

        response
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def is_repo_indexed_for_semantic_search?(repository:)
        return false unless cir = CopilotIndexedRepositories.find_by(repository: repository.id)
        cir.semantic_code_search_ok?
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

      sig { params(repository: Repository, user: User, token_number: Integer, closure_request_id: Integer).returns(T.nilable(SecretScanning::Errors::ServiceError)) }
      def update_token_with_closure_request_id(repository, user, token_number, closure_request_id)
        options = {
          repository_id: repository.id,
          token_number: token_number,
          closure_exemption_request_id: closure_request_id
        }
        response = GitHub::TokenScanning::Service::Client.new(user).update_token_with_closure_exemption_request_id(
          options
        )
        if response.error.present?
          Failbot.report(SecretScanning::Errors::Error.new("Unable to call update_token_with_closure_request_id"), app: FAILBOT_APP_NAME, alert_number: token_number, repository_id: repository.id, user_id: T.must(user).id, closure_exemption_request_id: closure_request_id)
          return SecretScanning::Errors::ServiceError.new(response.error.msg)
        end
        nil
      end

      private

      sig do
        params(
          permissions_collection: SecretScanning::Models::Permissions::PermissionsCollection,
          removed_permissions: T.nilable(T.any(GitHub::Proto::SecretScanning::Api::V2::PATV2Permissions, GitHub::Proto::SecretScanning::Api::V2::PATV1Permissions))
        )
         .returns(SecretScanning::Models::Permissions::PermissionsCollection)
      end
      def mark_permissions_as_deleted(permissions_collection, removed_permissions)
        unless removed_permissions.present?
          return permissions_collection
        end

        if removed_permissions.is_a?(GitHub::Proto::SecretScanning::Api::V2::PATV2Permissions)
          removed_permissions.permissions.each do |removed_permission|
            permissions_collection.mark_permission_in_group_as_deleted(
              SecretScanning::Models::Permissions::Fgp.value_to_display_group(removed_permission.permission),
              removed_permission.scope
            )
          end
          return permissions_collection
        end

        # must be a GitHub::Proto::SecretScanning::Api::V2::PATV1Permissions
        removed_permissions.scopes.each do |removed_scope|
          permissions_collection.mark_permission_anywhere_as_deleted(removed_scope)
        end
        permissions_collection
      end

      sig { params(comment: T.nilable(String)).returns(T.nilable(String)) }
      def normalize_dismissal_comment(comment)
        if comment.nil? || comment.empty?
          return nil
        end
        comment.encode("UTF-8", universal_newline: true)
      end

      sig { override.returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
      def current_copilot_user_v2; end

      sig { override.returns(T.nilable(User)) }
      def current_user; end
    end
  end
end
