# typed: true
# frozen_string_literal: true

module SlashCommands
  class TableCommand < ApplicationSlashCommand
    category :markdown

    trigger_on name: "table", title: "Table", description: "Add markdown table"

    menu :columns, breadcrumb: "Columns"
    menu :rows, breadcrumb: "Rows"
    fill :generate_table

    def columns
      items = [
        Item.new(id: "1-column", text: "1 column",  value: 1),
        Item.new(id: "2-columns", text: "2 columns", value: 2),
        Item.new(id: "3-columns", text: "3 columns", value: 3),
        Item.new(id: "4-columns", text: "4 columns", value: 4),
        Item.new(id: "5-columns", text: "5 columns", value: 5),
      ]

      menu(:columns, items: items)
    end

    def rows
      items = [
        Item.new(id: "1-row", text: "1 row", value: 1),
        Item.new(id: "2-rows", text: "2 rows", value: 2),
        Item.new(id: "3-rows", text: "3 rows", value: 3),
        Item.new(id: "4-rows", text: "4 rows", value: 4),
        Item.new(id: "5-rows", text: "5 rows", value: 5),
      ]

      menu(:rows, items: items)
    end

    def generate_table
      column_count = data[:columns].to_i
      row_count = data[:rows].to_i
      header_row = column_count.times.map { |_| " Header " }
      divider_row = column_count.times.map { |i| "-" * header_row[i].length }
      body_row = column_count.times.map { |_| " Cell " }

      body_rows = row_count.times.map { body_row }
      table = [
        header_row,
        divider_row,
        *body_rows
      ]

      table.map do |row|
        "|" + row.join("|") + "|"
      end.join("\n")
    end
  end
end
