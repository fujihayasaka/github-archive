class FileLock
  class LockTimeout < RuntimeError
    def initialize(lockfile)
      @lockfile = lockfile
    end

    def message
      "Failed to acquire lock #{@lockfile}"
    end
  end

  def initialize(lockfile:, timeout:)
    @lockfile = lockfile
    @timeout  = timeout
  end

  def synchronize
    file = nil

    begin
      Timeout.timeout(@timeout) do
        file = File.open(@lockfile, File::RDWR|File::CREAT, 0644)
        file.flock(File::LOCK_EX)
      end
    rescue Timeout::Error
      file.flock(File::LOCK_UN)
      raise LockTimeout.new(@lockfile)
    end

    yield
  ensure
    file&.close
  end
end
