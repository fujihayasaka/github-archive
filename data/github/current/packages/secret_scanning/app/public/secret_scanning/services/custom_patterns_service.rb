# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class CustomPatternsService
      include SecretScanning::Constants

      VALIDATE_ENABLED_REPOS_MAX = 1000
      GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE = "An error has occurred with custom patterns, please try again later."
      CUSTOM_PATTERNS_SERVICE_ERROR_TYPE = "CustomPatternsServiceError"

      # Maps internal proto validation error codes to public REST API codes.
      # The proto uses ROW_VERSION_MISMATCH but the public field is custom_pattern_version.
      VALIDATION_ERROR_CODE_MAPPINGS = T.let({
        "row_version_mismatch" => "custom_pattern_version_mismatch",
      }.freeze, T::Hash[String, String])

      # TODO - The actual return type for these CRUD custom pattern methods is Twirp::ClientResp[...] with some proto type as the type argument.
      # But ClientResp's type definition on error is incorrect; it says it's not nilable, but is is nilable.
      # And it causes Sorbet type errors when we nil check the error field.
      # Leave it T.untyped for now, and we can fix it later.

      sig { params(current_user: User).void }
      def initialize(current_user)
        @user = T.let(current_user, User)
        @client = T.let(GitHub::TokenScanning::Service::Client.new(current_user), GitHub::TokenScanning::Service::Client)
      end

      sig do
        params(options: T.any(T::Hash[Symbol, T.untyped], GitHub::Proto::SecretScanning::Api::V3::GetCustomPatternsRequest))
          .returns(T.nilable(Twirp::ClientResp[GitHub::Proto::SecretScanning::Api::V3::GetCustomPatternsResponse]))
      end
      def get_custom_patterns(options)
        @client.get_custom_patterns_paginated(options)
      end

      sig { params(ids: T::Array[Numeric], states: T::Array[Symbol]).returns(T.untyped) }
      def get_custom_patterns_by_id(ids, states = [])
        all_states = [:PUBLISHED, :DELETED, :DISABLED, :UNPUBLISHED]
        states_to_include = states.empty? ? all_states : states.select { |s| all_states.include?(s) }
        options = {}
        options[:selector] = {
          ids_selector: {
            ids: ids
          }
        }
        options[:filter] = {
          included_states: states_to_include,
        }
        @client.get_custom_patterns_paginated(options)
      end

      sig { params(id: Integer, selector: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
      def get_custom_pattern(id, selector)
        options = { **selector }
        options[:id] = id
        @client.get_custom_pattern(options)
      end

      sig do
        params(
          expression: String,
          display_name: String,
          post_processing: T::Hash[Symbol, T.untyped],
          selector: T::Hash[T.untyped, T.untyped],
          owner: T.any(Organization, Business, Repository),
          selected_repos: T.nilable(T::Array[Integer]),
        ).returns(T.untyped)
      end
      def add_custom_pattern(expression:, display_name:, post_processing:, selector:, owner:, selected_repos: nil)
        dry_run_repos = if selected_repos.nil?
          nil
        elsif owner.is_a?(Repository)
          nil
        else
          valid_repositories(owner, selected_repos)
        end

        response = @client.create_custom_pattern(
          expression: expression,
          display_name: display_name,
          post_processing: post_processing,
          dry_run_repositories: dry_run_repos,
          created_by_id: @user.id,
          **selector
        )

        if response&.error.nil? && response&.data&.custom_pattern.present? && response&.data&.error.blank?
          instrument_custom_pattern_event("create", response.data.custom_pattern, owner)
        end

        response
      end

      sig do
        params(
          id: Integer,
          expression: String,
          post_processing: T::Hash[Symbol, T.untyped],
          change_type: Symbol,
          owner_id: Integer,
          owner_scope: Integer,
          owner: T.any(Organization, Business, Repository),
          selected_repos: T.nilable(T::Array[Integer]),
          row_version: T.nilable(String),
        ).returns(T.untyped)
      end
      def update_custom_pattern(id:, expression:, post_processing:, change_type:, owner_id:, owner_scope:, owner:, selected_repos: nil, row_version: nil)
        dry_run_repos = if selected_repos.nil?
          nil
        elsif owner.is_a?(Repository)
          nil
        else
          valid_repositories(owner, selected_repos)
        end

        response = @client.update_custom_pattern(
          id: id,
          expression: expression,
          post_processing: post_processing,
          change_type: change_type,
          dry_run_repositories: dry_run_repos,
          row_version: row_version,
          updated_by_id: @user.id,
          owner_id: owner_id,
          owner_scope: owner_scope,
        )

        if response&.error.nil? && response&.data&.error.blank? && response&.data&.custom_pattern.present?
          instrument_custom_pattern_event("update", response.data.custom_pattern, owner)
        end

        response
      end

      sig do
        params(
          patterns_with_row_versions: T::Array[T::Hash[Symbol, T.nilable(T.any(Integer, String))]],
          owner_id: Integer,
          owner_scope: Integer,
          deleted_by_user_id: Integer,
          post_delete_action: T.nilable(Symbol)
        ).returns(T.untyped)
      end
      def delete_custom_patterns(patterns_with_row_versions:, owner_id:, owner_scope:, deleted_by_user_id:, post_delete_action:)
        @client.delete_custom_patterns(
          to_delete: patterns_with_row_versions,
          owner_id: owner_id,
          owner_scope: owner_scope,
          deleted_by_id: deleted_by_user_id,
          post_delete_action: post_delete_action)
      end

      sig do
        params(
          pattern_id: Integer,
          deleted_by_user_id: Integer,
          post_delete_action: T.nilable(Symbol),
          row_version: T.nilable(String),
          owner_id: Integer,
          owner_scope: Integer,
        ).returns(T.untyped)
      end
      def delete_custom_pattern(pattern_id:, deleted_by_user_id:, post_delete_action:, row_version:, owner_id:, owner_scope:)
        @client.delete_custom_pattern(
          id: pattern_id,
          deleted_by_id: deleted_by_user_id,
          post_delete_action: post_delete_action,
          row_version: row_version,
          owner_id: owner_id,
          owner_scope: owner_scope,
        )
      end

      sig do
        params(
          id: Integer,
          row_version: T.nilable(String),
          owner_id: Integer,
          owner_scope: Integer,
        ).returns(T.untyped)
      end
      def publish_custom_pattern(id:, row_version:, owner_id:, owner_scope:)
        @client.publish_custom_pattern(
          id: id,
          row_version: row_version,
          updated_by_id: @user.id,
          owner_id: owner_id,
          owner_scope: owner_scope,
        )
      end

      sig do
        params(
          display_name: String,
          source_string: String,
          expression: String,
          post_processing: T::Hash[Symbol, T.untyped],
        ).returns(T::Hash[T.untyped, T.untyped])
      end
      def test_custom_pattern(display_name:, source_string:, expression:, post_processing:)
        res = @client.get_pattern_matches(
          display_name: display_name,
          source_string: source_string,
          expression: expression,
          post_processing: post_processing,
        )

        error = nil
        if res&.data&.error&.present?
          error = res.data.error
        end

        has_wildcard_warning = res&.data&.warning&.type == :UNBOUNDED_WILDCARD

        pattern_matches = []
        if res&.data&.pattern_matches&.any?
          pattern_matches = res.data.pattern_matches.to_a
        end
        {
          pattern_matches: pattern_matches,
          error: error,
          has_wildcard_warning: has_wildcard_warning
        }
      end

      sig do
        params(
          id: Integer,
          push_protection_enabled: T::Boolean,
          owner_id: Integer,
          owner_scope: Integer,
          row_version: T.nilable(String),
        ).returns(T.untyped)
      end
      def update_custom_pattern_settings(id:, push_protection_enabled:, owner_id:, owner_scope:, row_version: nil)
        @client.update_custom_pattern_settings(
          id: id,
          push_protection_enabled: push_protection_enabled,
          owner_id: owner_id,
          owner_scope: owner_scope,
          updated_by_id: @user.id,
          row_version: row_version,
        )
      end

      sig { params(scope: Symbol, id: Integer).returns(T::Boolean) }
      def max_allowed_custom_patterns_created?(scope, id)
        options = {
          filter: {
            included_states: [:PUBLISHED]
          }
        }
        case scope
        when :repo
          options[:selector] = {
            repo_selector: {
              repository_id: id
            }
          }
        when :org
          options[:selector] = {
            org_selector: {
              owner_id: id
            }
          }
        when :business
          options[:selector] = {
            business_selector: {
              business_id: id
            }
          }
        end

        response = @client.get_custom_patterns_total_count(options)
        count = response&.data&.total_result_count || 0

        case scope
        when :repo
          return count >= GitHub.secret_scanning_max_custom_patterns_per_repo
        when :org
          return count >= GitHub.secret_scanning_max_custom_patterns_per_org
        when :business
          return count >= GitHub.secret_scanning_max_custom_patterns_per_business
        end
        false
      end

      sig do
        params(
          owner: T.nilable(T.any(Organization, Business)),
          selected_repo_ids: T::Array[Integer],
        ).returns(T.nilable(T::Array[Integer]))
      end
      def valid_repositories(owner, selected_repo_ids)
        return nil if owner.nil?
        secret_scanning_repos_set = validate_secret_scanning_repositories(selected_repo_ids)
        return nil if secret_scanning_repos_set.nil?

        secret_scanning_repos = secret_scanning_repos_set.to_a
        if owner.is_a?(Organization)
          # Ensure that the selected repos are still part of the organization
          secret_scanning_repos.intersection(owner.repositories.ids)
        elsif owner.is_a?(Business)
          # Ensure the following conditions are satisfied:
          # 1. The repo's organization belongs to the same business/enterprise as the custom pattern
          # 2. The repo's organization is adminable by the current user
          valid_repos = Repository.from_ids(secret_scanning_repos)
          .select do |repo|
            next false if repo.owner.nil?
            repo_owner = repo.owner
            if repo_owner&.organization?
              org = T.cast(repo.owner, Organization)
              org.business&.id == owner.id && ::SecurityProduct::Permissions::OrgAuthz.new(org, actor: @user).can_manage_secret_scanning_settings?
            elsif repo_owner&.user?
              ghas_for_emus = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(repo_owner)
              ghas_for_emus.feature_available? && ghas_for_emus.get_business&.id == owner.id && repo_owner.id == @user.id
            end
          end.to_a

          valid_repos.map { |repo| repo.id }
        end
      end

      sig { params(repo_ids: T::Array[Integer]).returns(T.nilable(T::Set[Integer])) }
      def validate_secret_scanning_repositories(repo_ids)
        enabled_repo_ids_set = Set.new
        repo_ids.each_slice(VALIDATE_ENABLED_REPOS_MAX) do |repo_ids_slice|
          response = @client.validate_enabled_repos({ repository_ids: repo_ids_slice })
          if response.nil? || response.error.present? || response.data.nil?
            Failbot.report(
              SecretScanning::Errors::ServiceError.new("validate enabled repos service call failed"),
              app: FAILBOT_APP_NAME,
              repo_ids: repo_ids_slice)
            return nil
          end
          enabled_repo_ids_set.merge(response&.data&.repository_ids.to_set)
        end
        enabled_repo_ids_set
      end

      sig { params(id: Integer, scan_ids: T.nilable(T::Array[Integer]), owner: T.any(Repository, Organization, Business), owner_scope: Symbol).returns(T::Boolean) }
      def cancel_dry_run_service(id:, scan_ids:, owner:, owner_scope:)
        options = {
          scan_ids: scan_ids,
          dry_run_scope: {
            custom_pattern_id: id,
            owner_id: owner.id,
            owner_scope: owner_scope,
          },
        }
        response = @client.cancel_dry_runs_for_custom_pattern(options)
        if response.nil? || response.error.present?
          Failbot.report(
            SecretScanning::Errors::ServiceError.new("cancel custom pattern dry run service call failed"),
            app: FAILBOT_APP_NAME,
            custom_pattern_id: id,
            owner_id: owner.id,
            owner_scope: owner_scope,
            scan_ids: scan_ids,
          )
          return false
        end
        true
      end

      sig do
        params(
          patterns: T::Array[T::Hash[Symbol, T.untyped]],
          owner_id: Integer,
          owner_scope: Symbol,
          owner: T.any(Organization, Business, Repository),
        ).returns([T.nilable(T::Array[GitHub::Proto::SecretScanning::Api::V3::SecretScanCustomPattern]), T.nilable(T::Hash[Integer, T::Hash[Symbol, T.untyped]]), T.nilable(StandardError)])
      end
      def batch_create_custom_patterns(patterns:, owner_id:, owner_scope:, owner:)
        req = GitHub::Proto::SecretScanning::Api::V3::BatchCreateCustomPatternsRequest.new(
          patterns: patterns.map do |p|
            GitHub::Proto::SecretScanning::Api::V3::CustomPatternToCreate.new(
              expression: p[:expression],
              display_name: p[:display_name],
              post_processing: p[:post_processing],
            )
          end,
          owner_id: owner_id,
          owner_scope: owner_scope,
          created_by_id: @user.id,
        )
        res = @client.batch_create_custom_patterns(req)
        is_err, err = SecretScanning::Services::ServiceHelper.process_response(
          response: res,
          operation: "batch creating custom patterns",
          is_404_ok: false,
          failbot_attributes: {},
        )
        return [nil, nil, err || SecretScanning::Errors::ServiceError.new("An error occurred")] if is_err || res.nil?

        data = res.data
        validation_errors = data.validation_errors
        unless validation_errors.length == 0
          errors_by_index = {}
          validation_errors.each do |index, errs|
            errors_by_index[index] = {
              errors: errs.errors.map do |e|
                code = e.code.to_s.downcase
                { code: VALIDATION_ERROR_CODE_MAPPINGS.fetch(code, code), message: e.message }
              end,
            }
          end
          return [nil, errors_by_index, nil]
        end

        created_patterns = data.created_patterns.to_a
        created_patterns.each { |pattern| instrument_custom_pattern_event("create", pattern, owner) }

        [created_patterns, nil, nil]
      end

      sig { params(description: String, examples: T.nilable(String)).returns(T.untyped) }
      def get_generated_expressions(description, examples)
        options = {
          description: description,
          examples: examples,
          user_id: @user.id,
        }

        @client.get_generated_expressions(options)
      end

      sig { params(res: T.untyped).returns([T.nilable(String), T.nilable(Symbol)]) }
      def check_for_custom_patterns_twirp_error(res)
        return GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE, nil if res.nil?
        return nil, nil if res.error.nil?
        [res.error.msg, res.error.code]
      end

      sig { params(msg: String, code: T.nilable(Symbol)).returns(T::Boolean) }
      def is_row_version_mismatch?(msg, code)
        return true if code == :failed_precondition && msg =~ /row_version/
        false
      end

      # Validates that all pattern IDs in a bulk delete request exist and that
      # their custom_pattern_version values match the current server-side versions.
      # Returns [error_message, code] following the same convention as
      # check_for_custom_patterns_twirp_error, or [nil, nil] if valid.
      #
      # TODO: Move per-pattern existence and row_version validation into TSS
      # (token-scanning-service). TSS currently only returns ErrRowVersionMismatch
      # when *all* patterns fail to match, silently skipping individual mismatches
      # in bulk deletes. Once TSS validates per-pattern, this Ruby-side check can
      # be removed.
      sig { params(to_delete: T::Array[T::Hash[Symbol, T.untyped]]).returns([T.nilable(String), T.nilable(Symbol)]) }
      def validate_custom_pattern_versions(to_delete)
        pattern_ids = to_delete.map { |p| p[:id] }
        res = get_custom_patterns_by_id(pattern_ids)

        if res.nil? || res.error.present?
          return GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE, nil
        end

        current_versions = T.let({}, T::Hash[Integer, String])
        res.data.custom_patterns.each do |pattern|
          current_versions[pattern.id.to_i] = pattern.row_version
        end

        to_delete.each do |p|
          current_version = current_versions[p[:id].to_i]
          if current_version.nil?
            return "pattern_id '#{p[:id]}' does not exist", :invalid_argument
          elsif current_version != p[:row_version]
            return "row_version mismatch", :failed_precondition
          end
        end

        [nil, nil]
      end

      private

      sig do
        params(
          action: String,
          custom_pattern: T.untyped,
          owner: T.any(Organization, Business, Repository),
        ).void
      end
      def instrument_custom_pattern_event(action, custom_pattern, owner)
        event_name = case owner
        when Business
          "business_secret_scanning_custom_pattern.#{action}"
        when Repository
          "repository_secret_scanning_custom_pattern.#{action}"
        when Organization
          "org_secret_scanning_custom_pattern.#{action}"
        end

        payload = {
          user: @user,
          custom_pattern: {
            id: custom_pattern.id,
            name: custom_pattern.display_name,
          },
        }

        case owner
        when Business
          payload[:business] = owner
        when Repository
          payload[:repo] = owner
          payload[:org] = owner.organization if owner.in_organization?
        when Organization
          payload[:org] = owner
        end

        GitHub.instrument(event_name, payload)
      end
    end
  end
end
