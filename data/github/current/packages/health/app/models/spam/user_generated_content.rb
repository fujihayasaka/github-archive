# typed: strict
# frozen_string_literal: true

module Spam
  module UserGeneratedContent
    extend T::Sig

    # Public: Has the user recently created content on any of these tables?
    # This is built to be as efficient as possible, so it returns early if
    # if it gets a true response from any of the tables.
    #
    # tables  - An array of strings or symbols of table names, like ["issues", "issue_comments"].
    # user_id - The id of the User being checked.
    # since:    The time since the user has created content.
    sig { params(tables: T::Array[T.any(String, Symbol)], user_id: Integer, since: ActiveSupport::Duration).returns(T::Boolean) }
    def self.has_recently_updated_content_on_any_table?(tables, user_id, since: 24.hours)
      tables.any? { |table| has_recently_updated_content?(table, user_id, since:) }
    end

    # Public: Has the user created content on this table since a given time?
    #
    # table   - The string or symbol table name, like "issues" or :discussion_comments.
    # user_id - The id of the User being checked.
    # since:    The time since the user has created content.
    sig { params(table: T.any(String, Symbol), user_id: Integer, since: ActiveSupport::Duration).returns(T::Boolean) }
    def self.has_recently_updated_content?(table, user_id, since: 24.hours)
      table = table.to_sym

      # Ignore followers and workflow_runs as they are not user generated content and
      # get removed when the account is deleted.
      return false if table.in?([:followers, :workflow_runs])

      klass = Spam::Spammable.tables_classes_including[table]
      return false unless klass

      since_column = klass.column_names.include?("updated_at") ? :updated_at : :created_at

      ActiveRecord::Base.connected_to(role: :reading) do
        klass.where(klass
          .arel_table[klass.spammable_user_foreign_key]
          .eq(user_id)
          .and(klass.arel_table[since_column].gt(since.ago))
        ).exists?
      end
    end
  end
end
