# typed: true
# frozen_string_literal: true

require "logger"

module GitHub::Pages::Management
  class SetVoting



    attr_reader :host, :voting, :delegate

    def initialize(host:, voting:, delegate:)
      @host = host
      @voting = !!voting
      @delegate = delegate
      nil
    end

    def perform
      affected_rows = ApplicationRecord::Domain::Repositories.connection.update(Arel.sql(<<-SQL, host: host, non_voting: !voting))
        UPDATE pages_fileservers SET non_voting = :non_voting WHERE host = :host
      SQL

      if affected_rows == 0
        delegate.log "No such host=#{host}"
        false
      else
        delegate.log "Set host=#{host} voting=#{voting}"
        true
      end
    end
  end
end
