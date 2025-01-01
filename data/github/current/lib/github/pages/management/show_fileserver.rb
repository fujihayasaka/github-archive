# typed: true
# frozen_string_literal: true

require "terminal-table"

module GitHub::Pages::Management
  class ShowFileserver

    attr_reader :delegate, :host

    def initialize(delegate:, host:)
      @delegate = delegate
      @host = host
      nil
    end

    def perform
      row = ApplicationRecord::Pages.connection.select_all(Arel.sql(<<-SQL, host: host)).to_a.first
        SELECT
          host,
          online,
          embargoed,
          evacuating,
          non_voting,
          datacenter,
          rack,
          ip,
          disk_free,
          disk_used,
          created_at
        FROM pages_fileservers
        WHERE host = :host
      SQL

      unless row
        delegate.log "Unable to find host=#{host}"
        return false
      end

      table = Terminal::Table.new headings: ["Hostname", row["host"]], rows: [
        ["Online?",     bool(row["online"])],
        ["Embargoed?",  bool(row["embargoed"])],
        ["Evacuating?", bool(row["evacuating"])],
        ["Voting?",     bool(row["non_voting"] ^ 1)],
        ["Data Center", row["datacenter"]],
        ["Rack",        row["rack"]],
        ["IP",          row["ip"]],
        ["Disk Used",   percent_used(row["disk_free"], row["disk_used"])],
        ["Created",     row["created_at"]],
      ]

      delegate.puts table.render

      true
    end

    def bool(value)
      value == 1 ? "Yes" : "No"
    end

    def percent_used(free, used)
      free = BigDecimal(free)
      used = BigDecimal(used)
      "#{((used / (used + free)) * 100).round(2)}%"
    end
  end
end
