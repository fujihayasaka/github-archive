# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class CodeScanning < Base

        class FilterType < T::Enum
          enums do
            CodeQLRule = new
            ThirdPartyRule = new
          end
        end

        sig { returns(::Business) }; attr_reader :business
        sig { returns(::User) }; attr_reader :user
        sig { returns(::UserSession) }; attr_reader :user_session
        sig { returns(FilterType) }; attr_reader :type
        sig { returns(T::Array[Organization]) }; attr_reader :authorized_orgs

        sig do
          params(
            business: ::Business,
            user: ::User,
            user_session: ::UserSession,
            type: FilterType,
            authorized_orgs: T::Array[Organization],
            kwargs: T.untyped
          ).void
        end
        def initialize(business:, user:, user_session:, type:, authorized_orgs:, **kwargs)
          super(**T.unsafe(kwargs))
          @business = business
          @user = user
          @user_session = user_session
          @type = type
          @authorized_orgs = authorized_orgs
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if authorized_orgs.empty?
          return [] unless type == FilterType::CodeQLRule || type == FilterType::ThirdPartyRule # Only rule filter is supported at this time

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

          suggestions.take(limit)
        end

        private

        sig { returns(::CodeScanning::AlertQueryService) }
        memoize def alert_query_service
          query = if type == FilterType::ThirdPartyRule
            "-tool:CodeQL"
          elsif type == FilterType::CodeQLRule
            "tool:CodeQL"
          else
            raise ArgumentError, "Unknown filter type: #{type}."
          end

          # Only include suggestions for alerts with security severities
          query += " severity:critical,high,medium,low"

          ::CodeScanning::AlertQueryService.for_business(
            business:,
            user:,
            user_session:,
            query: query,
            organizations: authorized_orgs,
            visibility: limited_visibility? ? "public" : nil
          )
        end

        sig { returns(T::Boolean) }
        memoize def limited_visibility?
          SecurityCenter::SecurityFeatures.limited_security_center_available?(business, dotcom_request_only: true)
        end
      end
    end
  end
end
