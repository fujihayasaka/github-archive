# Class used to simulate a logger for testing purposes.

module Tools
  class Logger
    def debug(&block)
      log("DEBUG", block.call)
    end

    def info(message, data = {})
      log("INFO", message, data)
    end

    private

    def log(level, message, data = {})
      timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      "[#{timestamp}] [#{level}] #{message} #{data.inspect}"
    end
  end
end