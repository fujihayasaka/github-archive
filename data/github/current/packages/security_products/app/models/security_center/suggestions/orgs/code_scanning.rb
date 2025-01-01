# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Orgs
      class CodeScanning < Base
        extend T::Sig

        class FilterType < T::Enum
          enums do
            CodeQLRule = new
            ThirdPartyRule = new
            AllRule = new
            Tool = new
          end
        end

        sig { returns(::Organization) }; attr_reader :organization
        sig { returns(::User) }; attr_reader :user
        sig { returns(::UserSession) }; attr_reader :user_session
        sig { returns(FilterType) }; attr_reader :type
        sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :allowed_repo_ids

        sig do
          params(
            organization: ::Organization,
            user: ::User,
            user_session: ::UserSession,
            type: FilterType,
            allowed_repo_ids: T.nilable(T::Array[Integer]),
            kwargs: T.untyped
          ).void
        end
        def initialize(organization:, user:, user_session:, type:, allowed_repo_ids:, **kwargs)
          super(**T.unsafe(kwargs))
          @organization = organization
          @user = user
          @user_session = user_session
          @type = type
          @allowed_repo_ids = allowed_repo_ids
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if allowed_repo_ids&.empty?

          suggestions = if type == FilterType::CodeQLRule || type == FilterType::ThirdPartyRule || type == FilterType::AllRule
            rule_suggestions
          elsif type == FilterType::Tool
            tool_suggestions
          else
            []
          end

          suggestions.take(limit)
        end

        private

        sig { returns(T::Array[Suggestion]) }
        memoize def rule_suggestions
          filter_options = alert_query_service.rules_for_org
          return [] if filter_options.empty?

          suggestions = T.let([], T::Array[Suggestion])
          filter_options.each do |rule|
            rule_label = rule.short_description
            rule_id = rule.sarif_identifier

            rule_id_downcase = rule_id.downcase
            next if selected_values.present? && selected_values.map(&:downcase).include?(rule_id_downcase)
            next if value.present? && rule_id_downcase.exclude?(value.downcase)

            suggestions << Suggestion.new(label: rule_label, value: rule_id, description: rule_id)
          end

          suggestions
        end

        sig { returns(T::Array[Suggestion]) }
        memoize def tool_suggestions
          filter_options = alert_query_service.tool_names_for_org
          return [] if filter_options.empty?

          suggestions = T.let([], T::Array[Suggestion])
          filter_options.each do |tool|
            tool_name = tool.name

            tool_name_downcase = tool_name.downcase
            next if selected_values.present? && selected_values.map(&:downcase).include?(tool_name_downcase)
            next if value.present? && tool_name_downcase.exclude?(value.downcase)

            suggestions << Suggestion.new(label: tool_name, value: tool_name, description: tool_name)
          end

          suggestions
        end

        sig { returns(::CodeScanning::AlertQueryService) }
        memoize def alert_query_service
          query = if type == FilterType::ThirdPartyRule
            "-tool:CodeQL"
          elsif type == FilterType::CodeQLRule
            "tool:CodeQL"
          elsif type == FilterType::AllRule || type == FilterType::Tool
            ""
          else
            raise ArgumentError, "Unknown filter type: #{type}."
          end

          if type != FilterType::AllRule && type != FilterType::Tool
            # Only include suggestions for alerts with security severities
            query += " severity:critical,high,medium,low"
          end

          ::CodeScanning::AlertQueryService.for_organization(
            organization:,
            user:,
            user_session:,
            query: query,
            allowed_repository_ids: allowed_repo_ids,
            visibility: limited_visibility? ? "public" : nil
          )
        end

        sig { returns(T::Boolean) }
        memoize def limited_visibility?
          SecurityCenter::SecurityFeatures.limited_security_center_available?(organization, dotcom_request_only: true)
        end
      end
    end
  end
end
