# typed: true
# frozen_string_literal: true

require "action_view/helpers/number_helper"

require "terminal-table"

module GitHub::Pages::Management
  class Status
    include ActionView::Helpers::NumberHelper

    attr_reader :delegate

    def initialize(delegate:)
      @delegate = delegate
      nil
    end

    def perform
      rows = ApplicationRecord::Domain::PagesFromRepositories.connection.select_rows(Arel.sql(<<-SQL))
        SELECT
          host,
          datacenter,
          online,
          embargoed,
          evacuating,
          non_voting,
          disk_free,
          disk_used,
          created_at
        FROM pages_fileservers
        ORDER BY non_voting, datacenter, host ASC
      SQL

      table = if !GitHub.enterprise?
        Terminal::Table.new(
          headings: ["Hostname", "Online?", "Embargoed?", "Evacuating?", "Voting?", "Created"],
          rows: rows.map do |hostname, _datacenter, online, embargoed, evacuating, non_voting, _, _, created|
            [hostname, bool(online), bool(embargoed), bool(evacuating), bool(non_voting ^ 1), created]
          end,
        )
      else
        Terminal::Table.new(
          headings: ["Hostname", "Online?", "Embargoed?", "Evacuating?", "Voting?", "Disk Free (Used %)", "Created"],
          rows: rows.map do |hostname, _datacenter, online, embargoed, evacuating, non_voting, disk_free, disk_used, created|
            [hostname, bool(online), bool(embargoed), bool(evacuating), bool(non_voting ^ 1), disk_space(disk_free, disk_used), created]
          end,
        )
      end

      delegate.puts table.render

      true
    end

    def bool(value)
      value == 1 ? "Yes" : "No"
    end

    def disk_space(free, used)
      free_kb = BigDecimal(free)
      used_kb = BigDecimal(used)
      "#{number_to_human_size(free_kb * 1024)} (#{((used_kb / (used_kb + free_kb)) * 100).round(2)}%)"
    end
  end
end
