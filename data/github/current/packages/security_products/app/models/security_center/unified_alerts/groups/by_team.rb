# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByTeam < Group
        extend T::Sig

        # Since it is for prototyping, the approach for team group type
        # is making an assumption of targered organizations have limited
        # teams and repositories. Setting a limit for safety.
        MAX_TEAM_REPO_LIMIT = 1_000

        sig do
          override.params(
            rel: ActiveRecord::Relation,
            security_feature: String
          ).returns(ActiveRecord::Relation)
        end
        def apply(rel, security_feature)
          repository_teams = T.let([], T::Array[String])
          scope.visible_teams_for(user).order(:organization_id, :slug).limit(MAX_TEAM_REPO_LIMIT).each do |team|
            repository_ids = team.direct_or_inherited_repo_ids(action: [:admin, :write]).uniq.compact
            next if repository_ids.empty?

            repository_ids.each do |repository_id|
              omit_column_name = repository_teams.size > 0
              repository_teams << "SELECT #{repository_id}#{omit_column_name ? "" : " AS `repository_id`"}, '#{team.slug}'#{omit_column_name ? "" : " AS `team`"}"
              break if repository_teams.size >= MAX_TEAM_REPO_LIMIT
            end
            break if repository_teams.size >= MAX_TEAM_REPO_LIMIT
          end

          # Intentionally fail the query if there are no teams with repositories
          return rel.select("0 AS `group`").none if repository_teams.empty?

          left_table_name = T.must(DataQuery::SECURITY_FEATURE_MODEL_MAPPINGS[security_feature]).table_name
          right_table_name = "repo_teams"

          rel
            .joins("RIGHT OUTER JOIN (#{Arel.sql(repository_teams.join(" UNION "))}) AS `#{right_table_name}` ON `#{right_table_name}`.`repository_id` = `#{left_table_name}`.`repository_id`")
            .select("#{right_table_name}.`team` AS `group`")
            .then do |rel|
              # To keep unmatched rows from RIGHT OUTER JOIN so we can include teams without alerts
              rel.or(rel.unscope(:where).where("`#{left_table_name}`.`id` IS NULL"))
            end
        end
      end
    end
  end
end
