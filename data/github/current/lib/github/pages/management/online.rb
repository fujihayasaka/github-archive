# typed: true
# frozen_string_literal: true

require "logger"

module GitHub::Pages::Management
  class Online

    attr_reader :host, :delegate

    def initialize(host:, delegate:)
      @host = host
      @delegate = delegate
      nil
    end

    def perform
      ApplicationRecord::Domain::PagesFromRepositories.connection.insert(Arel.sql(<<-SQL, host: host))
        INSERT INTO pages_fileservers (host, online, embargoed, evacuating, disk_free, disk_used, created_at, updated_at)
        VALUES (:host, 1, 1, 0, 0, 0, NOW(), NOW())
        ON DUPLICATE KEY UPDATE online = 1, updated_at = NOW()
      SQL

      delegate.log "Onlined host=#{host}"

      true
    end

  end
end
