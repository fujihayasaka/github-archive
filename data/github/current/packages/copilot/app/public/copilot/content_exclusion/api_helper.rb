# typed: strict
# frozen_string_literal: true

module Copilot
  module ContentExclusion
    module ApiHelper
      extend T::Sig

      RuleSource = T.type_alias { { name: String, type: String } }
      class ParsedRules < T::Struct
        extend T::Sig

        const :source, RuleSource
        const :paths, T::Array[String]
        const :if_none_match, T.nilable(T::Array[String])
        const :if_any_match, T.nilable(T::Array[String])

        sig { returns(String) }
        def to_json
          res = { source: source, paths: paths }
          res[:ifNoneMatch] = if_none_match if if_none_match
          res[:ifAnyMatch] = if_any_match if if_any_match
          res.to_json
        end
      end
      RulesPayload = T.type_alias { { rules: T::Array[ParsedRules], last_updated_at: ActiveSupport::TimeWithZone } }

      sig { params(copilot_user: Copilot::User, scope: String, url_strings: T::Array[String]).returns(T::Array[RulesPayload]) }
      def get_content_exclusion_rules(copilot_user, scope, url_strings)
        Kernel.raise Copilot::Errors::ContentExclusionError, "Invalid scope" unless Document::Scope::get_scopes.include?(scope)
        Kernel.raise Copilot::Errors::ContentExclusionError, "Invalid scope" if scope == Document::Scope::REPO && (url_strings.empty? || url_strings.all?(&:blank?))

        res = copilot_user.content_exclusion_rules_for_repo_urls(url_strings).map do |config_and_rules|
          rules_payload!(config_and_rules).merge(scope: Document::Scope::REPO)
        end

        if scope == Document::Scope::ALL
          all_files_rules = copilot_user.content_exclusion_rules_for_all_files
          res << rules_payload!(all_files_rules).merge(scope: Document::Scope::ALL)
        end

        res
      end

      sig { params(config_and_rules: Copilot::ContentExclusion::ConfigAndRules).returns(RulesPayload) }
      def rules_payload!(config_and_rules)
        last_updated_at = Time.zone.at(0)

        rules = config_and_rules.map do |config, rules|
          updated_at = config.updated_at
          if !updated_at.nil? && updated_at > last_updated_at
            last_updated_at = updated_at
          end

          source_name = T.let(config.resource_type == "Organization" ? config.resource.display_login : config.resource.name, String)

          if_none_match = nil
          if_any_match = nil

          if (config.organization || config.business)&.feature_enabled?(:copilot_text_based_content_exclusions_api)
            text_based_rules = rules.select(&:allow_text_based_rules)
            if text_based_rules.any?
              if_none_match_rules = text_based_rules.map(&:if_none_match).flatten
              if_any_match_rules = text_based_rules.map(&:if_any_match).flatten

              if_none_match = if_none_match_rules unless if_none_match_rules.all?(&:blank?)
              if_any_match = if_any_match_rules unless if_any_match_rules.all?(&:blank?)
            end
          end

          ParsedRules.new(
            source: { name: source_name, type: config.resource_type },
            paths: rules.map(&:patterns).flatten.uniq,
            if_none_match: if_none_match,
            if_any_match: if_any_match
          )
        end

        { rules:, last_updated_at: }
      end
    end
  end
end
