# typed: true
# frozen_string_literal: true

require "application_record/domain/storage"

module GitHub::Storage
  class Online
    def initialize(host:)
      @host = host
    end

    def perform
      affected_rows = ApplicationRecord::Domain::Storage.connection.update(Arel.sql(<<-SQL, host: @host))
        UPDATE storage_file_servers
        SET online=1
        WHERE host=:host
        LIMIT 1
      SQL

      affected_rows == 1
    end
  end
end
