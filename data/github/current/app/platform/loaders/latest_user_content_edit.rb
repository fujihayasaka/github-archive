# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class LatestUserContentEdit < Platform::Loader
      def self.load(user_content_editable, model_id)
        self.for(user_content_editable).load(model_id)
      end

      def initialize(user_content_editable)
        @user_content_type = user_content_editable.name
      end

      def fetch(model_ids)
        edit_class = UserContentEditable.edit_class_for(user_content_type).constantize
        column_name = edit_class.attribute_aliases["user_content_id"] || "user_content_id"
        quoted_table_name = edit_class.quoted_table_name

        bind_vars = [model_ids]
        user_content_condition = ""
        if edit_class == UserContentEdit
          bind_vars << user_content_type
          user_content_condition = "AND user_content_type = ?"
        end

        results = edit_class.find_by_sql([<<~SQL, *bind_vars])
          SELECT #{quoted_table_name}.*
          FROM #{quoted_table_name}
          INNER JOIN (
            SELECT #{column_name}, MAX(id) AS max_id
            FROM #{quoted_table_name}
            WHERE #{column_name} IN (?) #{user_content_condition}
            GROUP BY #{column_name}
          ) AS maxt ON #{quoted_table_name}.id = maxt.max_id
        SQL

        results.inject({}) do |fulfillments, user_content_edit|
          fulfillments[user_content_edit.user_content_id] = user_content_edit
          fulfillments
        end
      end

      private

      attr_reader :user_content_type
    end
  end
end
