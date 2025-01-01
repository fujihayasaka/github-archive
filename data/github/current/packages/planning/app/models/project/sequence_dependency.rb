# typed: false
# frozen_string_literal: true

class Project
  # This module provides the sequence context required for creating the project numbering
  # sequence.
  #
  # Note! This module is shared by Project and MemexProject since they use the same url paths
  # and need to ensure there are no conflicts with the number.
  module SequenceDependency
    include Sequence::Context

    def sequence_context_type
      "ProjectOwner::#{owner_type}"
    end

    def sequence_context_id
      owner_id
    end

    def create_sequence_if_missing
      unless Sequence.exists?(self)
        # In case a Project or MemexProject somehow already exists for this context
        # but we are missing a sequence, start it from the largest existing number
        projects_sql = Arel.sql(<<-SQL, owner_id: owner_id, owner_type: owner_type)
          SELECT MAX(number) AS num FROM projects WHERE (owner_id = :owner_id AND owner_type = :owner_type)
        SQL
        memex_sql = Arel.sql(<<-SQL, owner_id: owner_id, owner_type: owner_type)
          SELECT MAX(number) AS num FROM memex_projects WHERE (owner_id = :owner_id AND owner_type = :owner_type)
        SQL

        start_value = [
          Project.connection.select_value(projects_sql) || 0,
          MemexProject.connection.select_value(memex_sql) || 0
        ].max
        Sequence.create(self, start_value)
      end
    end
  end
end
