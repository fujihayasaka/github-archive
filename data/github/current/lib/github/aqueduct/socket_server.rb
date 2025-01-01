# typed: true
# frozen_string_literal: true

require "socket"

# A per-process RPC server that responds to commands sent over a UNIX socket.
#
# Example server usage:
#
#   server = SocketServer.new(file: "/tmp/sock")
#   server.on("status") { "HI"}
#   server.run
#
# Example client usage:
#
#   $ echo status | nc -U /tmp/sock
#   HI
#
module GitHub
  module Aqueduct
    class SocketServer
      def initialize(file:, read_timeout: 1)
        @file = file
        @handlers = {}
        @read_timeout = read_timeout
      end

      def on(command, &block)
        @handlers[command] = block
      end

      def run
        server = create_server(@file)
        loop do
          begin
            socket = server.accept
          rescue StandardError => e
            GitHub.logger.error("Error accepting socket connection: #{e}")
            sleep 1
            next
          end

          begin
            unless IO.select([socket], nil, nil, @read_timeout)
              socket.close
              next
            end

            command = socket.gets&.strip

            if handler = @handlers[command]
              begin
                socket.puts(handler.call.to_s)
              rescue => e # rubocop:todo Lint/GenericRescue
                socket.puts("ERROR: #{e}")
              end
            else
              socket.puts("ERROR: unknown command #{command.inspect}")
            end

            socket.close
          rescue Errno::EPIPE
            # Ignore when clients close sockets
          rescue StandardError => e
            GitHub.logger.error("Error handling socket request: #{e}")
          end
        end
      ensure
        File.unlink(@file) if File.exist?(@file)
      end

      def create_server(file)
        File.delete(file) if File.exist?(file)
        server = UNIXServer.new(file)
        File.chmod(666, file)
        server
      end

    end
  end
end
