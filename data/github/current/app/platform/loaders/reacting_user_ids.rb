# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ReactingUserIds < Platform::Loader
      include Scientist

      QUERY_UNION_BATCH_SIZE = 64

      def self.load(subject, content, limit: 11)
        self.for(subject.class.name, limit).load([subject.id, content])
      end

      def initialize(subject_type, limit)
        @subject_type = subject_type
        @limit = limit
      end

      def fetch(subject_ids_and_content)
        subject_ids_by_content = Hash.new { |h, k| h[k] = [] }
        subject_ids_and_content.each do |subject_id, content|
          subject_ids_by_content[content] << subject_id
        end

        model_class = if ::Reactable::SUBJECT_TYPES_WITH_SEPARATE_REACTION_MODELS.include?(@subject_type)
          "#{@subject_type}Reaction".constantize
        else
          Reaction
        end

        queries = subject_ids_by_content.flat_map do |content, subject_ids|
          subject_ids.map do |subject_id|
            query = if model_class == Reaction
              Reaction.where(
                subject_type: @subject_type,
                subject_id: subject_id,
                content: content).
              select([:content, :user_id, :subject_id])
            else
              model_class.
                where(model_class.subject_association => subject_id).
                where(content: content).
                select([:content, :user_id, model_class.subject_association_column_name.to_sym])
            end
            if GitHub.spamminess_check_enabled?
              query = query.where(user_hidden: false)
            end
            query.order("created_at ASC, id ASC").limit(@limit).to_sql
          end
        end

        # Split the queries to 64 queries max per batch. This to work around a Vitess bug which can handle
        # at max 64 union queries at the same time.
        # Later flatten the results [content, user_id, subject_id] and turn the result to a set.
        results = queries.
          each_slice(QUERY_UNION_BATCH_SIZE).
          flat_map { |queries_slice| model_class.connection.select_rows(Arel.sql("(#{queries_slice.join(") UNION (")})")) }

        reacted_user_ids_by_subject_id_and_content = Hash.new { |h, k| h[k] = [] }
        results.each do |content, user_id, subject_id|
          reacted_user_ids_by_subject_id_and_content[[subject_id, content]] << user_id
        end

        reacted_user_ids_by_subject_id_and_content
      end
    end
  end
end
