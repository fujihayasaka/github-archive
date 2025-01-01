# typed: true
# frozen_string_literal: true

class CopilotSpace
  # This module provides the sequence context required for creating the custom_copilot numbering
  # sequence.
  module SequenceDependency
    extend T::Helpers
    include Sequence::Context

    requires_ancestor { CopilotSpace }

    def sequence_context_type
      "CustomCopilot::#{owner_type}"
    end

    def sequence_context_id
      owner_id
    end

    def create_sequence_if_missing
      unless Sequence.exists?(self)
        # In case an item somehow already exists for this context
        # but we are missing a sequence, start it from the largest existing number
        sequence_sql = Arel.sql(<<-SQL, owner_id: owner_id, owner_type: owner_type)
          SELECT MAX(number) AS num FROM custom_copilots WHERE (owner_id = :owner_id AND owner_type = :owner_type)
        SQL
        start_value = CopilotSpace.connection.select_value(sequence_sql) || 0
        Sequence.create(self, start_value)
      end
    end
  end
end
