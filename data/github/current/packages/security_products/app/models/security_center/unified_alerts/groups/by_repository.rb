# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByRepository < Group
        extend T::Sig

        sig do
          override.params(
            rel: ActiveRecord::Relation,
            security_feature: String
          ).returns(ActiveRecord::Relation)
        end
        def apply(rel, security_feature)
          rel
            .joins(:repository_metadata)
            .select(Arel.sql("`#{SecurityOverviewAnalytics::Repository.table_name}`.`name` AS `group`"))
        end
      end
    end
  end
end
