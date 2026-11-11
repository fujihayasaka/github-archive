# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class EditedByAnotherUser < Platform::Loader

      attr_reader :user_content_table, :user_content_type, :user_content_class

      def self.load(user_content_class, model_id)
        self.for(user_content_class).load(model_id)
      end

      def initialize(user_content_class)
        @user_content_class = user_content_class
        @user_content_table = user_content_class.table_name
        @user_content_type = user_content_class.name
      end

      def fetch(user_content_ids)
        ids_with_owners = user_content_class.where(id: user_content_ids).pluck(:id, :user_id)

        edit_class = UserContentEditable.edit_class_for(user_content_type).constantize
        values = if edit_class != UserContentEdit
          scope = ids_with_owners.inject(edit_class.none) do |result, (id, owner_id)|
            result.or(edit_class.where(user_content_id: id).where.not(editor_id: owner_id))
          end

          scope.distinct.pluck(:user_content_id)
        else
          sql = Arel.sql(<<~SQL, user_content_type: user_content_class.name, user_content_ids: user_content_ids)
            SELECT DISTINCT user_content_id
            FROM user_content_edits AS edits
            WHERE edits.user_content_type = :user_content_type
              AND edits.user_content_id IN (:user_content_ids)
              AND (
          SQL
          ids_with_owners[0..-2].each do |id, owner_id| # all but last tuple, which needs special handling
            sql += Arel.sql(<<~SQL, id: id, owner_id: owner_id)
              (edits.user_content_id = :id AND edits.editor_id <> :owner_id) OR
            SQL
          end

          sql += Arel.sql(<<~SQL, id: ids_with_owners.last[0], owner_id: ids_with_owners.last[1])
            (edits.user_content_id = :id AND edits.editor_id <> :owner_id)
            )
          SQL

          ::UserContentEdit.connection.select_values(sql)
        end

        values.flatten.each_with_object(Hash.new(false)) do |content_id, result|
          result[content_id] = true
        end
      end
    end
  end
end
