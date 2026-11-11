# frozen_string_literal: true

require "minitest/autorun"
require "mocha/minitest"
require "authnd-client"
require "fileutils"

TEST_PORT = "18081"

def start_server(addr)
  FileUtils.mkdir_p "tmp"

  out_file = "tmp/server.out"
  err_file = "tmp/server.err"
  @env = { "AUTHND_PORT" => TEST_PORT, "SKIP_BUILD" => "1", "AUTHND_DISABLE_LOCAL_MOBILE_CLIENT" => "true" }
  start_server_cmd ||= ENV.fetch("AUTHND_BIN_PATH", "script/api")
  @pid = Process.spawn(@env, start_server_cmd, out: out_file, err: err_file)

  begin
    await_connection(addr, timeout: 30)
  rescue Timeout::Error => e
    puts "authnd server not listening on #{addr} after 30 seconds"
    puts "==== Server output:"
    puts File.read(out_file)
    puts "==== Server error:"
    puts File.read(err_file)
    raise e
  end
end

def stop_server
  system("kill -9 $(lsof -i tcp:#{TEST_PORT} -t)")
  Process.kill("TERM", @pid) if @pid
end

def await_connection(addr, timeout: 30)
  Timeout.timeout(timeout) do
    until listening_service?(addr)
      sleep 1
      puts "Waiting authnd server at #{addr} to listen..."
    end
  end
end

def listening_service?(addr, timeout: 5)
  host, port = addr.split(":", 2)
  Timeout.timeout(timeout) do
    socket = TCPSocket.new(host, port)
    socket&.close
    true
  rescue Errno::ECONNREFUSED
    false
  end
end
