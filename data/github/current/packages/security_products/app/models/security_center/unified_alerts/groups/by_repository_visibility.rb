# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByRepositoryVisibility < Group
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
            .select(Arel.sql(%{CASE `#{SecurityOverviewAnalytics::Repository.table_name}`.`visibility`
              WHEN 0 THEN 'public'
              WHEN 1 THEN 'private'
              WHEN 2 THEN 'internal'
              END AS `group`}.squish))
        end
      end
    end
  end
end
