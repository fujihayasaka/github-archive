# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ReactionGroups < Platform::Loader
      def self.load(subject)
        self.for(subject.class.name).load(subject)
      end

      def initialize(subject_type)
        @subject_type = subject_type
      end

      def fetch(subjects)
        GitHub.tracer.in_span(
          "Platform::Loader::ReactionGroups#fetch",
          kind: :internal,
          attributes: {
            "gh.reactions.subject.count" => subjects.size,
            "gh.reactions.subject.type" => @subject_type,
            "gh.reactions.subject.user_hiden" => GitHub.spamminess_check_enabled?
          }
        ) do
          results = reactions(subjects: subjects)
          grouped_results = Hash.new { [0, nil] }
          results.each do |subject_id, content, total_count, created_at|
            grouped_results[[subject_id, content]] = [total_count, created_at]
          end

          # Returns a hash of { subject => [ reaction_group, ... ], ... }
          subjects.index_with do |subject|
            subject.class.emotions.map do |emotion|
              total_count, created_at = grouped_results[[subject.id, emotion.content]]
              ::ReactionGroup.new(
                subject: subject,
                emotion: emotion,
                total_count: total_count,
                created_at: created_at
              )
            end
          end
        end
      end

      def reactions(subjects:)
        if ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(@subject_type.to_s)
          klass = "#{@subject_type}Reaction".constantize
          bindings = {
            table: Arel.sql(klass.to_s.tableize),
            subject_id_column: Arel.sql("#{@subject_type.to_s.underscore}_id"),
            subject_ids: subjects.map(&:id),
          }
          reactions_sql = Arel.sql(<<~SQL, **bindings)
            SELECT :subject_id_column, content, COUNT(*) as total_count, MIN(created_at) as created_at
            FROM :table
            WHERE :subject_id_column IN (:subject_ids)
          SQL

          if GitHub.spamminess_check_enabled?
            reactions_sql += Arel.sql <<~SQL
              AND user_hidden = false
            SQL
          end

          reactions_sql += Arel.sql(<<~SQL, subject_id_column: bindings[:subject_id_column])
            GROUP BY :subject_id_column, content
          SQL

          klass = "#{@subject_type}Reaction".constantize
          GitHub.tracer.in_span(
            "Platform::Loader::ReactionGroups#reaction.select_rows",
            kind: :internal,
          ) do
            klass.connection.select_rows(reactions_sql)
          end
        else
          reactions_sql = Arel.sql(<<~SQL, subject_type: @subject_type, subject_ids: subjects.map(&:id))
            SELECT subject_id, content, COUNT(*) as total_count, MIN(created_at) as created_at
            FROM reactions
            WHERE subject_type = :subject_type AND subject_id IN (:subject_ids)
          SQL

          if GitHub.spamminess_check_enabled?
            reactions_sql += Arel.sql <<~SQL
              AND user_hidden = false
            SQL
          end

          reactions_sql += Arel.sql <<~SQL
            GROUP BY subject_id, content
          SQL
          GitHub.tracer.in_span(
            "Platform::Loader::ReactionGroups#reaction.select_rows",
            kind: :internal,
          ) do
            Reaction.connection.select_rows(reactions_sql)
          end
        end
      end
    end
  end
end
