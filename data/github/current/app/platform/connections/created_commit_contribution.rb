# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class CreatedCommitContribution < Connections::Base
      total_count_field description: <<~DESCRIPTION
        Identifies the total count of commits across days and repositories in the connection.
      DESCRIPTION

      def total_count
        contribs_by_repo = @object.parent
        contribs_by_repo.total_count
      end
    end
  end
end
