# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByCustomProperty < Group
        extend T::Sig
        include GitHub::Memoizer

        GROUP_KEY_PREFIX = "repo.props"

        # Since it is for prototyping, the approach for custom property group type
        # is making an assumption of targered organizations have limited
        # number of customer property values and repositories. Setting a limit for safety.
        MAX_CUSTOM_PROPERTY_REPO_LIMIT = 1_000

        sig do
          override.params(
            rel: ActiveRecord::Relation,
            security_feature: String
          ).returns(ActiveRecord::Relation)
        end
        def apply(rel, security_feature)
          property_definition = self.property_definition

          # Since it is for prototyping, the approach for custom property group type
          # is making an assumption of targered organizations have limited
          # custom property values and repositories.
          #
          # Thus intentionally fails the query if property not found or it is a string value type
          return rel.select("0 AS `group`").none if property_definition.nil? || property_definition.string_value_type?

          repository_property_values = T.let([], T::Array[String])
          property_definition
            .custom_property_values
            .where(custom_property_values: {
              target_type: ::Repository.name,
              target_id: ::Repository.where(owner: scope).select(:id)
            })
            .limit(MAX_CUSTOM_PROPERTY_REPO_LIMIT)
            .distinct
            .pluck(:target_id, :value).each do |repository_id, property_value|
              omit_column_name = repository_property_values.size > 0
              repository_property_values << "SELECT #{repository_id}#{omit_column_name ? "" : " AS `repository_id`"}, '#{property_value}'#{omit_column_name ? "" : " AS `property_value`"}"
            end
          return rel.select("0 AS `group`").none if repository_property_values.empty?

          left_table_name = T.must(DataQuery::SECURITY_FEATURE_MODEL_MAPPINGS[security_feature]).table_name
          right_table_name = "repo_properties"

          rel
            .joins("RIGHT OUTER JOIN (#{Arel.sql(repository_property_values.join(" UNION "))}) AS `#{right_table_name}` ON `#{right_table_name}`.`repository_id` = `#{left_table_name}`.`repository_id`")
            .select("#{right_table_name}.`property_value` AS `group`")
            .then do |rel|
              # To keep unmatched rows from RIGHT OUTER JOIN so we can include property values without alerts
              rel.or(rel.unscope(:where).where("`#{left_table_name}`.`id` IS NULL"))
            end
        end

        sig do
          override
            .params(items: T::Array[GroupDataQuery::AlertGroupData])
            .returns(T::Array[GroupDataQuery::AlertGroupData])
        end
        def finalize(items)
          property_definition = self.property_definition
          return items if property_definition.nil?

          # For now, only prefixing for boolean-type properties, as it looks confusing to have groups named "true" / "false"
          return items unless property_definition.true_false_value_type?

          items.each do |item|
            item[:name] = "#{property_definition.property_name}: #{item[:name]}"
          end
        end

        private

        sig { returns(T.nilable(::CustomPropertyDefinition)) }
        memoize def property_definition
          property_name = group_key.delete_prefix("#{GROUP_KEY_PREFIX}.")
          ::CustomPropertyDefinition.for(scope).where(property_name:).first
        end
      end
    end
  end
end
