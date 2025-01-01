# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class GroupLookup
        extend T::Sig
        extend T::Helpers
        abstract!

        GROUP_KEY_TO_TYPE_MAPPINGS = T.let({
          "tool" => ByTool,
          "severity" => BySeverity,
          "repo" => ByRepository,
          "repo.visibility" => ByRepositoryVisibility,
          "team" => ByTeam,
          "topic" => ByTopic,
          "dependabot.advisory" => ByAdvisory,
        }, T::Hash[String, T.class_of(Group)])

        sig { params(group_key: String, scope: ::Organization, user: ::User).returns(T.nilable(Group)) }
        def self.from(group_key, scope:, user:)
          group_class = GROUP_KEY_TO_TYPE_MAPPINGS[group_key.downcase]
          return group_class.new(scope:, user:, group_key:) if group_class.present?
          return ByCustomProperty.new(scope:, user:, group_key:) if group_key.start_with?(ByCustomProperty::GROUP_KEY_PREFIX)
          nil
        end
      end
    end
  end
end
