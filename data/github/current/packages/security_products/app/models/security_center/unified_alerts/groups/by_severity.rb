# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class BySeverity < Group
        extend T::Sig

        sig do
          override.params(
            rel: ActiveRecord::Relation,
            security_feature: String
          ).returns(ActiveRecord::Relation)
        end
        def apply(rel, security_feature)
          feature_table_name = T.must(DataQuery::SECURITY_FEATURE_MODEL_MAPPINGS[security_feature]).table_name
          group_column = case security_feature
          when SecurityFeatures::SECRET_SCANNING
            "'CRITICAL' AS `group`"
          when SecurityFeatures::CODE_SCANNING
            "IF(`#{feature_table_name}`.`alert_severity` IS NULL, 'INFORMATIONAL', `#{feature_table_name}`.`alert_severity`) AS `group`"
          else
            "IF(`#{feature_table_name}`.`alert_severity` = 'MODERATE', 'MEDIUM', `#{feature_table_name}`.`alert_severity`) AS `group`"
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
            item[:key] = "#{group_key}:#{item[:name].parameterize}"
            item[:name] = item[:name].titleize
          end
        end
      end
    end
  end
end
