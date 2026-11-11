# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class CliEvents
      include Events

      def initialize(io: $stdout)
        @io = io
        @records_complete = 0

        on_progress_with_count do |count|
          increment_and_print_record_count("added to export", count)
        end
      end

      # Internal: Increment records complete counter and print progress to cli.
      def increment_and_print_record_count(action, increment_by = 1)
        @records_complete += increment_by

        @io.print "#{@records_complete} models #{action}\r"
      end
    end
  end
end
