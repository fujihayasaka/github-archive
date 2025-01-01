# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByAdvisory < Group
        extend T::Sig

        sig do
          override.params(
            rel: ActiveRecord::Relation,
            security_feature: String
          ).returns(ActiveRecord::Relation)
        end
        def apply(rel, security_feature)
          return rel.select("0 AS `group`").none unless rel.klass == SecurityOverviewAnalytics::DependabotAlertRevision

          rel.select(Arel.sql("`#{SecurityOverviewAnalytics::DependabotAlertRevision.table_name}`.`ghsa_id` AS `group`"))
        end

        sig do
          override
            .params(items: T::Array[GroupDataQuery::AlertGroupData])
            .returns(T::Array[GroupDataQuery::AlertGroupData])
        end
        def finalize(items)
          groups_by_ghsa = items.index_by { |i| i[:name] }

          vulnerabilities_by_ghsa = Vulnerability
            .where(ghsa_id: groups_by_ghsa.keys)
            .where.not(summary: nil)
            .pluck(:ghsa_id, :summary)
            .to_h

          # Translate GHSA ID into advisory summary/title
          items.each do |item|
            ghsa_id = item[:name]
            item[:name] = vulnerabilities_by_ghsa[ghsa_id] if vulnerabilities_by_ghsa.key?(ghsa_id)
          end
        end
      end
    end
  end
end
