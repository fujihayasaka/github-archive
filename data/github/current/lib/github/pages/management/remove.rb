# typed: true
# frozen_string_literal: true

require "logger"

module GitHub::Pages::Management
  class Remove


    attr_reader :host, :delegate

    def initialize(host:, delegate:)
      @host = host
      @delegate = delegate
      nil
    end

    def perform
      host_is_online = ApplicationRecord::Domain::PagesFromRepositories.connection.select_value(Arel.sql(<<-SQL, host: host))
        SELECT online FROM pages_fileservers WHERE host = :host
      SQL

      if host_is_online.nil?
        delegate.log "Unknown host=#{host}"
        return false
      end

      if host_is_online == 1
        delegate.log "Cannot remove host=#{host}; must be offline to remove"
        return false
      end

      remove_pages_fileserver(host: host)
    end

    def remove_pages_fileserver(host:)
      affected_rows = ApplicationRecord::Domain::PagesFromRepositories.connection.delete(Arel.sql(<<-SQL, host: host))
        DELETE FROM pages_fileservers WHERE host = :host
      SQL

      if affected_rows == 0
        delegate.log "Could not remove host=#{host}"
        false
      else
        delegate.log "Removed host=#{host}"
        true
      end
    end

  end
end
