# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class IncludesCreatedEdit < Platform::Loader
      attr_reader :user_content_type

      def self.load(user_content_editable, model_id)
        self.for(user_content_editable).load(model_id)
      end

      def initialize(user_content_editable)
        @user_content_type = user_content_editable.name
      end

      def fetch(user_content_ids)
        edit_ids = first_and_second_edit_ids(user_content_ids)
        edited_at_by_content_id = edited_at_by_content_id(edit_ids)

        edited_at_by_content_id.each_with_object(Hash.new(false)) do |(content_id, edits), result|
          first_edited_at, second_edited_at = edits
          result[content_id] = first_edited_at == second_edited_at
        end
      end

      private

      # Private: Finds first and second user content edit ids for the given set
      # of content IDs. If there are less than two edits for a given content ID,
      # no edit IDs are returned for it.
      #
      # user_content_id  - An Array of Integer IDs
      #
      # Returns an Array of user_content_edit IDs.
      def first_and_second_edit_ids(user_content_ids)
        edit_class = UserContentEditable.edit_class_for(user_content_type).constantize
        results = if edit_class != UserContentEdit
          column_name = edit_class.attribute_aliases["user_content_id"]
          quoted_table_name = edit_class.quoted_table_name

          edit_class.connection.select_rows(Arel.sql(<<~SQL, user_content_ids: user_content_ids))
            SELECT first_edit.id, MIN(second_edit.id)
            FROM #{quoted_table_name} AS second_edit
            INNER JOIN (
                SELECT #{column_name}, MIN(id) AS id
                FROM #{quoted_table_name}
                WHERE #{column_name} IN (:user_content_ids)
                GROUP BY #{column_name}
            ) AS first_edit ON first_edit.#{column_name} = second_edit.#{column_name}
            WHERE
              second_edit.id <> first_edit.id
            GROUP BY second_edit.#{column_name}
          SQL
        else
          UserContentEdit.connection.select_rows(Arel.sql(<<~SQL, user_content_type: user_content_type, user_content_ids: user_content_ids))
            SELECT first_edit.id, MIN(second_edit.id)
            FROM user_content_edits AS second_edit
            INNER JOIN
              (
                SELECT user_content_type, user_content_id, MIN(id) AS id
                FROM user_content_edits
                WHERE user_content_type = :user_content_type
                  AND user_content_id IN (:user_content_ids)
                GROUP BY user_content_id
              )
              AS first_edit
              ON first_edit.user_content_type = second_edit.user_content_type
                AND first_edit.user_content_id = second_edit.user_content_id
            WHERE
              second_edit.id <> first_edit.id
            GROUP BY second_edit.user_content_id
          SQL
        end

        results.flatten
      end

      # Private: Finds the created_at timestamp for each specified user_content_edit and
      # groups the results by user_content_id.
      #
      # edit_ids  - An Array of user_content_edit IDs.
      #
      # Returns a Hash.
      def edited_at_by_content_id(edit_ids)
        return {} if edit_ids.none?

        edit_class = UserContentEditable.edit_class_for(user_content_type).constantize
        results = if edit_class != UserContentEdit
          edit_class.where(id: edit_ids).pluck(:user_content_id, :created_at)
        else
          UserContentEdit.connection.select_rows(Arel.sql(<<~SQL, edit_ids: edit_ids))
            SELECT user_content_id, created_at
            FROM user_content_edits
            WHERE id IN (:edit_ids)
          SQL
        end

        results.each_with_object({}) do |(content_id, edited_at), by_content_id|
          by_content_id[content_id] ||= []
          by_content_id[content_id] << edited_at
        end
      end
    end
  end
end
