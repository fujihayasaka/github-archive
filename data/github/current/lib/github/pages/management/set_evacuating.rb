# typed: true
# frozen_string_literal: true

require "logger"

module GitHub::Pages::Management
  class SetEvacuating



    attr_reader :host, :evacuating, :delegate

    def initialize(host:, evacuating:, delegate:)
      @host = host
      @evacuating = !!evacuating
      @delegate = delegate
      nil
    end

    def perform
      affected_rows = ApplicationRecord::Domain::Repositories.connection.update(Arel.sql(<<-SQL, host: host, evacuating: evacuating))
        UPDATE pages_fileservers SET evacuating = :evacuating WHERE host = :host
      SQL

      if affected_rows == 0
        delegate.log "No such host=#{host}"
        false
      else
        delegate.log "Set host=#{host} evacuating=#{evacuating}."
        true
      end
    end
  end
end
