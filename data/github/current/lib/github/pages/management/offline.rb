# typed: true
# frozen_string_literal: true

require "logger"

module GitHub::Pages::Management
  class Offline


    attr_reader :host, :delegate

    def initialize(host:, delegate:)
      @host = host
      @delegate = delegate
      nil
    end

    def perform
      affected_rows = ApplicationRecord::Pages.connection.update(Arel.sql(<<-SQL, host: host))
        UPDATE pages_fileservers SET online = 0 WHERE host = :host
      SQL

      if affected_rows == 0
        delegate.log "No such host=#{host}"
        false
      else
        delegate.log "Offlined host=#{host}"
        true
      end
    end
  end
end
