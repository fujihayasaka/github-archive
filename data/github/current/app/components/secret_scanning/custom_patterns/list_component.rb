# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class ListComponent < ApplicationComponent
      include SecretScanningCustomPatternsHelper
      QUERY_PARSER = Search::Queries::SecretScanning::CustomPatternsQuery
      include FeatureFlagHelper

      attr_reader :pattern_model

      delegate  :get_delete_custom_pattern_path,
                :get_delete_custom_patterns_path,
                :get_show_custom_pattern_path,
                :get_new_custom_pattern_path,
                :secret_scanning_custom_patterns_blankslate_header,
                :secret_scanning_max_custom_patterns,
                :secret_scan_custom_patterns_count,
                :no_matching_results?,
                :token_scanning_service_unavailable?,
                :secret_scanning_custom_patterns_error,
                :display_new_custom_pattern_header?,
                :pattern_unpublished?,
                :current_user_id,
                :secret_scan_custom_patterns,
                :cursor_path,
                :service_response,
                :cursor_disabled?,
                :previous_cursor,
                :next_cursor,
                :has_pagination?,

                :query,
                :suggestable_items,
                :scope,
                :total_count,

                :has_default_is_values?, to: :pattern_model

      sig { params(pattern_model: BaseSecretScanningCustomPatternsModel).void }
      def initialize(pattern_model:)
        @pattern_model = pattern_model
      end

      class BaseSecretScanningCustomPatternsModel
        include GitHub::Memoizer

        def initialize
          @query_parser = QUERY_PARSER.new(query: @query)
          @query = @query_parser.query
          @states = @query_parser.status_enum
          @sort_order = @query_parser.sort_enum
          @push_protected_filter = @query_parser.push_protected_filter_enum
        end

        def scope
          @scope
        end

        def has_default_is_values?
          @query_parser.has_default_is_values?
        end

        sig { returns(T::Boolean) }
        def has_valid_statuses?
          @states.any?
        end

        def set_selector(options)
          options[:selector] = {
            @scope_key => @scope_selector
          }
          options
        end

        def total_count
          return @total_count if defined? @total_count
          options = {}
          options = set_selector(options)

          options[:filter] = {
            included_states: @states,
            push_protected_filter: @push_protected_filter
          }

          res = GitHub::TokenScanning::Service::Client.new(@user).get_custom_patterns_total_count(options)
          count = res&.data&.total_result_count
          @total_count = count
        end

        sig { returns(T.nilable(Twirp::ClientResp[GitHub::Proto::SecretScanning::Api::V3::GetCustomPatternsResponse])) }
        memoize def service_response
          return nil unless has_valid_statuses?

          options = {}
          options = set_selector(options)

          unless @cursor.nil?
            options[:cursor] = Base64.urlsafe_decode64(@cursor)
          end

          options[:sort_order] = @sort_order
          options[:filter] = {
            included_states: @states,
            push_protected_filter: @push_protected_filter
          }

          SecretScanning::Services::CustomPatternsService.new(@user).get_custom_patterns(options)
        end

        def query
          @query
        end

        def previous_cursor
          return @previous_cursor if defined? @previous_cursor

          previous_cursor = service_response&.data&.previous_cursor
          unless previous_cursor.nil?
            previous_cursor = Base64.urlsafe_encode64(previous_cursor)
          end
          @previous_cursor = previous_cursor
        end

        def next_cursor
          return @next_cursor if defined? @next_cursor

          next_cursor = service_response&.data&.next_cursor
          unless next_cursor.nil?
            next_cursor = Base64.urlsafe_encode64(next_cursor)
          end
          @next_cursor = next_cursor
        end

        def cursor_disabled?(cursor)
          cursor.nil? || cursor.empty?
        end

        def has_pagination?
          return false if token_scanning_service_unavailable?
          return false if previous_cursor.nil? && next_cursor.nil?
          if total_count == 0 && secret_scan_custom_patterns_count != 0
            return false
          end
          return false if total_count < SecretScanningCustomPatternsHelper::CUSTOM_PATTERNS_PAGE_SIZE + 1

          true
        end

        def token_scanning_service_unavailable?
          return false unless has_valid_statuses?
          service_response.nil? || service_response&.data.nil? || service_response&.error.present?
        end

        sig { returns(Integer) }
        def secret_scan_custom_patterns_count
          secret_scan_custom_patterns.count
        end

        sig { returns(T::Array[GitHub::Proto::SecretScanning::Api::V3::SecretScanCustomPattern]) }
        memoize def secret_scan_custom_patterns
          service_response&.data&.custom_patterns&.to_a || []
        end

        sig { params(pattern: GitHub::Proto::SecretScanning::Api::V3::SecretScanCustomPattern).returns(T::Boolean) }
        def pattern_unpublished?(pattern)
          pattern.state == :UNPUBLISHED
        end
      end

      class RepoSecretScanningCustomPatternsModel < BaseSecretScanningCustomPatternsModel
        include UrlHelpers

        def initialize(repo:, user:, cursor:, query: "")
          @repo = repo
          @user = user
          @cursor = cursor
          @query = query
          @scope_selector = {
            repository_id: @repo.id
          }
          @scope = :repo
          @scope_key = :repo_selector
          super()
        end

        def get_delete_custom_pattern_path(id:)
          delete_custom_pattern_path(id: id, repository: @repo, user_id: @repo.owner.display_login)
        end

        def get_delete_custom_patterns_path
          delete_custom_patterns_path(repository: @repo, user_id: @repo.owner.display_login)
        end

        def get_new_custom_pattern_path
          new_custom_pattern_path(repository: @repo, user_id: @repo.owner.display_login)
        end

        def get_show_custom_pattern_path(id:)
          show_custom_pattern_path(id: id, repository: @repo, user_id: @repo.owner.display_login)
        end

        def secret_scanning_custom_patterns_blankslate_header
          "There are no custom patterns for this repository"
        end

        def secret_scanning_custom_patterns_error
          "Failed to load custom patterns for this repository"
        end

        def secret_scanning_max_custom_patterns
          GitHub.secret_scanning_max_custom_patterns_per_repo
        end

        sig { returns(T::Boolean) }
        def no_matching_results?
          return true unless has_valid_statuses?
          secret_scan_custom_patterns_count == 0
        end

        # Returns true if a header with a link to documentation needs to be displayed.
        def display_new_custom_pattern_header?
          true
        end

        def current_user_id
          nil
        end

        def cursor_path
          repository_security_and_analysis_path(repository: @repo, user_id: @repo.owner.display_login, previous_cursor: previous_cursor, next_cursor: next_cursor, query: query)
        end
      end

      class OrgSecretScanningCustomPatternsModel < BaseSecretScanningCustomPatternsModel
        include UrlHelpers

        def initialize(org:, user:, cursor:, query: "")
          @cursor = cursor
          @user = user
          @org = org
          @query = query
          @scope_selector = {
            owner_id: @org.id
          }
          @scope = :org
          @scope_key = :org_selector
          super()
        end

        def get_delete_custom_pattern_path(id:)
          settings_org_security_analysis_delete_custom_pattern_path(id: id, organization_id: @org.display_login)
        end

        def get_delete_custom_patterns_path
          settings_org_security_analysis_delete_custom_patterns_path(organization_id: @org.display_login)
        end

        def get_new_custom_pattern_path
          settings_org_security_analysis_new_custom_pattern_path(organization_id: @org.display_login)
        end

        def get_show_custom_pattern_path(id:)
          settings_org_security_analysis_show_custom_pattern_path(id: id, organization_id: @org.display_login)
        end

        def secret_scanning_custom_patterns_blankslate_header
          "There are no custom patterns for this organization"
        end

        def secret_scanning_custom_patterns_error
          "Failed to load custom patterns for this organization"
        end

        def secret_scanning_max_custom_patterns
          GitHub.secret_scanning_max_custom_patterns_per_org
        end

        sig { returns(T::Boolean) }
        def no_matching_results?
          return true unless has_valid_statuses?
          secret_scan_custom_patterns_count == 0
        end

        # Returns true if a header with a link to documentation needs to be displayed.
        def display_new_custom_pattern_header?
          true
        end

        def current_user_id
          nil
        end

        def cursor_path
          settings_org_security_analysis_path(organization_id: @org.display_login, org: @org, previous_cursor: previous_cursor, next_cursor: next_cursor, query: query)
        end
      end

      class EnterpriseSecretScanningCustomPatternsModel < BaseSecretScanningCustomPatternsModel
        include UrlHelpers

        def initialize(business:, user:, cursor:, query: "")
          @business = business
          @user = user
          @cursor = cursor
          @query = query
          @scope_selector = {
            business_id: @business.id
          }
          @scope = :business
          @scope_key = :business_selector
          super()
        end

        def get_delete_custom_pattern_path(id:)
          settings_business_delete_custom_pattern_enterprise_path(id: id, slug: @business.slug, user_id: @user.display_login)
        end

        def get_delete_custom_patterns_path
          settings_business_delete_custom_patterns_enterprise_path(slug: @business.slug, user_id: @user.display_login)
        end

        def get_new_custom_pattern_path
          settings_business_new_custom_pattern_enterprise_path(slug: @business.slug, user_id: @user.display_login)
        end

        def get_show_custom_pattern_path(id:)
          settings_business_show_custom_pattern_enterprise_path(id: id, slug: @business.slug, user_id: @user.display_login)
        end

        def secret_scanning_custom_patterns_blankslate_header
          "There are no custom patterns for this enterprise"
        end

        def secret_scanning_custom_patterns_error
          "Failed to load patterns for this enterprise"
        end

        def secret_scanning_max_custom_patterns
          GitHub.secret_scanning_max_custom_patterns_per_business
        end

        sig { returns(T::Boolean) }
        def no_matching_results?
          return true unless has_valid_statuses?
          secret_scan_custom_patterns_count == 0
        end

        # Returns true if a header with a link to documentation needs to be displayed. Enterprise has a different experience, so we return false.
        def display_new_custom_pattern_header?
          false
        end

        def current_user_id
          @user.id
        end

        def cursor_path
          settings_security_analysis_policies_security_features_enterprise_path(slug: @business.slug, previous_cursor: previous_cursor, next_cursor: next_cursor, query: query)
        end
      end
    end
  end
end
