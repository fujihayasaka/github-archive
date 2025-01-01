# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class Tool < Base

        sig { returns(SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser) }; attr_reader :security_features_parser

        sig do
          params(
            security_features_parser: SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser,
            skip_limit: T::Boolean,
            kwargs: T.untyped
          ).void
        end
        def initialize(security_features_parser:, skip_limit: false, **kwargs)
          super(**T.unsafe(kwargs))
          @security_features_parser = security_features_parser
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          tools = [Suggestion.new({ label: "All GitHub tools", value: "github" })]
          tools += [
            Suggestion.new({ label: "Dependabot", value: "dependabot" }),
            Suggestion.new({ label: "Secret scanning", value: "secret-scanning" }),
            Suggestion.new({ label: "CodeQL", value: "codeql" }),
          ].select { |suggestion| security_features_parser.visible_frontend_security_features.include?(suggestion.value) }

          if security_features_parser.visible_frontend_security_features.include?(SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser::TOOL_CODEQL)
            tools << Suggestion.new({ label: "All third-party tools", value: "third-party" })
            tools += security_features_parser.allowed_third_party_tools.map { |tool_name| Suggestion.new(label: tool_name, value: tool_name) }
          end

          tools = tools.select { |tool| tool.value.downcase.include?(value.downcase) && !selected_values.map(&:downcase).include?(tool.label&.downcase) }
          tools
        end
      end
    end
  end
end
