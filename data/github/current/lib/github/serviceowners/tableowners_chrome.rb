# typed: true
# frozen_string_literal: true

module GitHub
  class Serviceowners
    class TableownersChrome
      HELP_MESSAGE = <<~EOS
        Tip: the table above is markdown compatible and can be pasted on issues and PRs
        Tip2: run bin/tableowners to fill blanks with the first suggestion

        In case of trouble, call the #monolith-platform team on Slack.
      EOS

      MISMATCHED_OWNERSHIP = "There are %{count} table owner definitions where the table's owner doesn't match its models' owners! Please, update %{yaml_path} and/or SERVICEOWNERS and assign each of the following tables/models to the service they belong:"

      INVALID_OWNERSHIP = "There are %{count} table owner definitions where the service doesn't exist in %{yaml_path} (maybe it's a typo?)! Please, update %{yaml_path} and assign each of the following tables to the service they belong:"

      MISSING_TABLES = "There are %{count} table owner definitions where the table doesn't exist in the " +
        "database (maybe it's a typo?)! Please, update %{yaml_path} and correct/remove the following tables:"

      UNOWNED_TABLES = "There are %{count} table owner definitions missing! Please update %{yaml_path} " +
        "and assign the following tables to the service they belong:"

      def initialize
        @tableowners = Tableowners.new
      end

      def verify_all
        [
          verify_all_tables_have_owners,
          verify_all_owned_tables_exist,
          verify_owner_validity,
          verify_ownership
        ].compact.join("\n\n")
      end

      def verify_all_tables_have_owners
        unowned_tables = results.select(&:table_exists?).reject(&:in_yaml?)
        verify(unowned_tables, UNOWNED_TABLES)
      end

      def verify_all_owned_tables_exist
        missing_tables = results.reject(&:table_exists?).select(&:in_yaml?)
        verify(missing_tables, MISSING_TABLES)
      end

      def verify_owner_validity
        undefined_owners = results.select(&:in_yaml?).reject(&:owner_exists?)
        verify(undefined_owners, INVALID_OWNERSHIP)
      end

      def verify_ownership
        mismatches = results.select(&:in_yaml?).select(&:mismatch?)
        verify(mismatches, MISMATCHED_OWNERSHIP)
      end

      private

      def verify(results, message_template)
        return if results.empty?

        report_error(message_template % { count: results.count, yaml_path: yaml_path }, results)
      end

      def report_error(message, results)
        <<~EOS
          #{message}

          #{markdown_table(results, :table, :owner, :owner_suggestions)}

          #{HELP_MESSAGE}
        EOS
      end

      def results
        @tableowners.results.values
      end

      def yaml_path
        @tableowners.tableowners_yaml_path.relative_path_from(Rails.root)
      end

      # newer versions of terminal-table have proper support for markdown so
      # this could be simplified when it's updated
      def markdown_table(table_infos, *keys)
        rows = table_infos.map do |table_info|
          table_info.to_h.values_at(*keys).map do |value|
            case value
            when Array
              value.join(", ")
            else
              value.to_s
            end
          end
        end
        headings = keys.map(&:to_s).map(&:humanize)
        table_table = Terminal::Table.new(
          rows: rows,
          headings: headings,
          style: {
            border_x:      "-",
            border_y:      "|",
            border_i:      "|"
          }
        ).to_s.split("\n")[1..-2].join("\n")
      end
    end
  end
end
