# typed: true
# frozen_string_literal: true

require "logger"

module GitHub::Pages::Management
  class SetFileserverAttribute

    ALLOWED_ATTRIBUTES = [
      :datacenter, :ip, :online, :rack
    ].freeze

    attr_reader :host, :attribute, :value, :delegate

    def initialize(host:, attribute:, value:, delegate:)
      @host = host
      @attribute = attribute
      @delegate = delegate
      @value = value
      nil
    end

    def perform
      unless ALLOWED_ATTRIBUTES.include?(attribute)
        delegate.log "Unable to set attribute '#{attribute}' for host=#{host}"
        return false
      end

      affected_rows = ApplicationRecord::Domain::Repositories.connection.update(Arel.sql(<<-SQL, host: host, attribute: Arel.sql(attribute.to_s), value: value))
        UPDATE pages_fileservers SET :attribute = :value WHERE host = :host
      SQL

      if affected_rows == 0
        delegate.log "No such host=#{host}"
        false
      else
        delegate.log "Set host=#{host} #{attribute}=#{value.inspect}"
        true
      end
    end
  end
end
