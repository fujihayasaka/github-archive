# typed: true
# frozen_string_literal: true

module GlobalIdMigration
  module Formatting
    class Json
      def initialize(data)
        @data = data
      end

      def format
        @data.to_json
      end
    end

    class Code
      def initialize(data)
        @data = data
      end

      def format
        code = <<~CODE
          implements_node templates: %{templates}, as: "%{prefix}", ready_date: %{ready_date} do |%{object_name}|
            # implementation logic goes here.
          end
        CODE

        code % {
          templates: @data["suggested_templates"].map { |t| t.map(&:to_sym) },
          prefix: @data["suggested_prefix"],
          object_name:  @data["object_type"].split("::").last.underscore,
          ready_date: !@data["ready_date"].blank? ? "#{@data["ready_date"]}" : "nil",
        }
      end
    end

    class Markdown
      def initialize(data)
        @data = data
      end

      def format
        md = "|#{@data["headers"].join("|")}|\n"
        md += "|-" * @data["headers"].count + "|\n"

        @data["rows"].each do |row|
          md += "|#{row.join("|")}|\n"
        end

        md
      end
    end
  end
end
