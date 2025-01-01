# typed: true
# frozen_string_literal: true

module GitRPC
  class Client
    def count_lines(oids)
      return {} if oids.empty?
      send_message(:count_lines, oids)
    end
  end
end
