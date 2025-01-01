# typed: true
# frozen_string_literal: true

require "minitest/autorun"
require "minitest/test"

require_relative "setup/mocks"

require "socket"
require "notifyd"

class Config
  ADDRESS = ENV["NOTIFYD_SERVER_ADDRESS"] || "localhost:8080"
  BIN_PATH = ENV["NOTIFYD_BIN_PATH"] || "../bin/api"
  HMAC_KEY = ENV["TWIRP_API_HMAC_KEYS"]&.split&.first || "secret"
  VERBOSE = ENV["VERBOSE"] || false

  def self.bin_path
    BIN_PATH
  end

  def self.hmac_key
    HMAC_KEY
  end

  def self.address
    ADDRESS
  end

  def self.url
    "http://#{ADDRESS}"
  end

  def self.output
    return "/dev/stdout" if VERBOSE

    "/dev/null"
  end
end

class TestServer
  # Starts the notifyd go api server
  # - address: address the server will run on
  # - bin_path: path to the binary of the server
  # - hmac_key: hmac_key we want the server to use for our tests
  # - output: where to send the output of the notifyd api process, default is /dev/null
  def self.start(address: Config.address, bin_path: Config.bin_path, hmac_key: Config.hmac_key, output: Config.output)
    env = { "TWIRP_API_HMAC_KEYS" => hmac_key, "APP_ENV" => "test" }
    @pid = Process.spawn(env, bin_path, [:out, :err] => output) if bin_path

    # Ensure the server has started and ready for us before continuing
    await_connection(address)
  end

  def self.stop
    return unless @pid
    Process.kill("TERM", @pid)
    Process.wait(@pid)
  end

  def self.await_connection(address, timeout: 30)
    sleep 0.25
    Timeout.timeout(timeout) do
      until listening_service?(address)
        sleep 1
        puts "Waiting for notifyd server at #{address} to listen..."
      end
    end
  end

  def self.listening_service?(address, timeout: 5)
    host, port = address.split(":", 2)

    Timeout.timeout(timeout) do
      socket = ::TCPSocket.new(host, port)
      socket.close unless socket.nil?
      true
    rescue Errno::ECONNREFUSED
      false
    end
  end
end
