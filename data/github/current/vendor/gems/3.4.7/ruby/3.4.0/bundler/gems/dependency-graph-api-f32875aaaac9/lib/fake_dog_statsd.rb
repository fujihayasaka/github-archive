require "socket"

class FakeDogStatsd
  MSG_MAX = 10_000

  def self.run(**kwargs)
    new(**kwargs).run
  end

  def initialize(host:, port:, output:)
    @host   = host
    @port   = port
    @output = output
  end

  def run
    while data = socket.recv(MSG_MAX)
      stat, _ = data
      output << stat
    end
  rescue Interrupt
  end

  private

  attr_reader :host, :port, :output

  def socket
    @socket ||= UDPSocket.new.tap { |socket| socket.bind(host, port) }
  end
end
