# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByTopic < Group
        extend T::Sig
        include GitHub::Memoizer

        # Since it is for prototyping, the approach for topic group type
        # is making an assumption of targered organizations have limited
        # topics and repositories. Setting a limit for safety.
        MAX_TOPIC_REPO_LIMIT = 1_000

        sig do
          override.params(
            rel: ActiveRecord::Relation,
            security_feature: String
          ).returns(ActiveRecord::Relation)
        end
        def apply(rel, security_feature)
          topic_repos_lookup = T.let(
            ::RepositoryTopic
              .applied
              .joins(:repository)
              .where(repository: { owner: scope })
              .order(:repository_id, :topic_id)
              .limit(MAX_TOPIC_REPO_LIMIT)
              .pluck(:repository_id, :topic_id),
            T::Array[[Integer, Integer]]
          ).group_by { |_, topic_id| topic_id }

          repository_topics = T.let([], T::Array[String])
          ::Topic.where(id: topic_repos_lookup.keys).pluck(:id, :name).each do |id, name|
            repository_ids = topic_repos_lookup[id]&.map { |repository_id, _| repository_id }&.uniq&.compact
            next if repository_ids.blank?

            repository_ids.each do |repository_id|
              omit_column_name = repository_topics.size > 0
              repository_topics << "SELECT #{repository_id}#{omit_column_name ? "" : " AS `repository_id`"}, '#{name}'#{omit_column_name ? "" : " AS `topic`"}"
            end
          end

          # Intentionally fail the query if there are no repositories with topics
          return rel.select("0 AS `group`").none if repository_topics.empty?

          left_table_name = T.must(DataQuery::SECURITY_FEATURE_MODEL_MAPPINGS[security_feature]).table_name
          right_table_name = "repo_topics"

          rel
            .joins("RIGHT OUTER JOIN (#{Arel.sql(repository_topics.join(" UNION "))}) AS `#{right_table_name}` ON `#{right_table_name}`.`repository_id` = `#{left_table_name}`.`repository_id`")
            .select("#{right_table_name}.`topic` AS `group`")
            .then do |rel|
              # To keep unmatched rows from RIGHT OUTER JOIN so we can include topics without alerts
              rel.or(rel.unscope(:where).where("`#{left_table_name}`.`id` IS NULL"))
            end
        end
      end
    end
  end
end
