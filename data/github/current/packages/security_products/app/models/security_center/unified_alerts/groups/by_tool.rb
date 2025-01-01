# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByTool < Group
        extend T::Sig

        FIRST_PARTY_TOOLS = T.let([
          "Dependabot",
          "CodeQL",
          "Secret scanning",
        ].freeze, T::Array[String])

        sig do
          override.params(
            rel: ActiveRecord::Relation,
            security_feature: String
          ).returns(ActiveRecord::Relation)
        end
        def apply(rel, security_feature)
          group_column = case security_feature
          when SecurityFeatures::SECRET_SCANNING
            "'Secret scanning' AS `group`"
          when SecurityFeatures::DEPENDABOT_ALERTS
            "'Dependabot' AS `group`"
          else
            "`tool` AS `group`"
          end

          rel.select(Arel.sql(group_column))
        end

        sig do
          override
            .params(items: T::Array[GroupDataQuery::AlertGroupData])
            .returns(T::Array[GroupDataQuery::AlertGroupData])
        end
        def finalize(items)
          # Normalize casing for severity types
          items.each do |item|
            if FIRST_PARTY_TOOLS.include?(item[:name])
              item[:key] = "#{group_key}:#{item[:name].parameterize}"
            elsif item[:name].include?(" ")
              # If the tool name includes spaces, we need to quote
              # The filter control does this for us, but here we're trying to emulate that behavior,
              # as group keys are used as filters when fetching list items for a group.
              item[:key] = "#{group_key}:\"#{item[:name]}\""
            else
              item[:key] = "#{group_key}:#{item[:name]}"
            end
          end
        end
      end
    end
  end
end
