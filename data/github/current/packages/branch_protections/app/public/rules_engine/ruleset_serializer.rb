# typed: strict
# frozen_string_literal: true

module RulesEngine
  module RulesetSerializer
    extend T::Sig

    LESS_THAN = T.let(GitHub::HTMLSafeString.make("&lt;"), String)
    GREATER_THAN = T.let(GitHub::HTMLSafeString.make("&gt;"), String)

    # Return the ruleset as a hash
    #
    # @param ruleset [RepositoryRuleset] The repository ruleset to serialize
    # @param user [User] The user viewing the serialized data
    # @param is_stafftools [Boolean] Whether this is being serialized for stafftools
    sig { params(ruleset: RepositoryRuleset, user: T.nilable(User), is_stafftools: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
    def self.ruleset_hash(ruleset, user: nil, is_stafftools: false)
      Api::Serializer.serialize(
        :repository_ruleset_hash,
        ruleset, {
          request_source: ruleset.source,
          current_user: user, # user viewing the serialized data
          staff_authorized: user&.metadata&.is_staff? && is_stafftools
        }
      ).except(:node_id, :_links, :created_at, :updated_at, :id, :current_user_can_bypass)
    end

    # Return the ruleset history serialized as a string for html
    # @param ruleset [RepositoryRuleset] The repository ruleset to serialize
    # @param user [User] The user viewing the serialized data
    # @param is_stafftools [Boolean] Whether this is being serialized for stafftools
    sig { params(history: RepositoryRulesetHistory, user: T.nilable(User), is_stafftools: T::Boolean).returns(T.nilable(String)) }
    def self.history_to_html_string(history, user: nil, is_stafftools: false)
      return nil if history.deserialized.blank?
      hash = ruleset_hash(history.ruleset_from_state, user:, is_stafftools:)
      pretty_json = JSON.pretty_generate(hash)
      pretty_json
        .gsub("<", LESS_THAN)
        .gsub(">", GREATER_THAN)
        .gsub(/\n/, GitHub::HTMLSafeString::BR)
        .gsub(/ /, GitHub::HTMLSafeString::NBSP)
    end
  end
end
