require 'uri'
require 'socket'

module Rover
  class Error < StandardError; end

  def self.report!
    rover_bootstrap = ENV.delete("ROVER_BOOTSTRAP_SERVER")
    return unless rover_bootstrap

    rover_server_uri = URI.parse(rover_bootstrap)
    rover_credentials, rover_server = rover_server_uri.userinfo, rover_server_uri.path
    rover_connection = UNIXSocket.new(rover_server)

    begin
      rover_connection.write("CHECKIN #{rover_credentials}\n")
      while rover_message = rover_connection.gets
        next if rover_message == "ACK\n"
        if rover_message != "OK\n"
          raise Rover::Error, "couldn't checkin to rover: #{rover_message}"
        end
        break
      end
    ensure
      rover_connection.close
    end
  end
end
