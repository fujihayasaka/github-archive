# rubocop:disable Style/FrozenStringLiteralComment
# RPC calls for getting server-related information.
module GitRPC
  class Backend
    # Public: Get one-, five-, and fifteen-minute load.
    rpc_reader :loadavg, no_git_repo: true
    def loadavg
      case RUBY_PLATFORM
      when /darwin/
        res = spawn(["uptime"])
        raise LoadAverageFailed, res["err"] unless res["ok"]
        md = /load averages: ([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)/.match(res["out"])
        raise LoadAverageFailed, "Pattern does not match \"#{res["out"]}\"" unless md
        md[1..3].map { |s| s.to_f }
      when /linux/
        str = File.read("/proc/loadavg")
        str.split[0..2].map { |s| s.to_f }
      else
        raise LoadAverageFailed, "Unknown RUBY_PLATFORM: #{RUBY_PLATFORM}"
      end
    end

    # Get some approximate age-related values
    #
    # This is used in `script/dgit-server` so that a human has an idea of
    # how old a server is.
    rpc_reader :uptime_and_age, no_git_repo: true
    def uptime_and_age
      case RUBY_PLATFORM
      when /darwin/
        {
          # h/t https://github.com/delano/sysinfo/blob/c5f3967caa6f8603124978f0396dbff0c8f9a3d2/lib/sysinfo.rb#L220
          :uptime_seconds => (Time.now.to_f - Time.at(`sysctl -b kern.boottime 2>/dev/null`.unpack("L").first).to_f).to_f,
          # h/t https://www.howtogeek.com/194186/bragging-rights-how-to-find-your-computers-uptime-and-installation-date/
          :provisioned_at => File.exist?("/var/log/install.log") ? File.stat("/var/log/install.log").birthtime : nil,
        }
      when /linux/
        {
          :uptime_seconds => File.read("/proc/uptime").to_f,
          :provisioned_at => File.exist?("/etc/inittab") ? File.stat("/etc/inittab").mtime : nil,
        }
      else
        {}
      end
    end

    rpc_reader :cpu_count, no_git_repo: true
    def cpu_count
      command = case RUBY_PLATFORM
      when /darwin/
        ["sysctl", "-n", "hw.physicalcpu"]
      when /linux/
        ["grep", "-c", "^processor", "/proc/cpuinfo"]
      end

      res = spawn(command)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].to_i
    end

    rpc_reader :replica_count, no_git_repo: true
    def replica_count(gists_only: false, repos_only: false)
      command = if gists_only
        ["sh", "-c", %q{cat /data/repositories/?/index.txt | grep -Pc '/gist/[0-9a-f]+\.git$'}]
      elsif repos_only
        ["sh", "-c", %q{cat /data/repositories/?/index.txt | grep -Pc '/\d+/\d+\.git$'}]
      else
        ["sh", "-c", "wc -l /data/repositories/?/index.txt"]
      end
      res = spawn(command)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      line = res["out"].split("\n").last
      line.to_i
    end

    rpc_reader :host_metadata, no_git_repo: true
    def host_metadata
      GitRPC.host_metadata
    end

    rpc_reader :host_encrypted?, no_git_repo: true
    def host_encrypted?
      return false if RUBY_PLATFORM =~ /darwin/ && ENV["RAILS_ENV"] != "test"

      res = spawn(["/bin/lsblk", "-P", "--noheadings", "--output=mountpoint,type"])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]

      mounts = res["out"].split("\n").map { |line| line.split(" ") }.to_h

      return false if mounts['MOUNTPOINT="/data/repositories"'] != 'TYPE="crypt"'
      return false if mounts['MOUNTPOINT="/data/lariatcache"'] != 'TYPE="crypt"'
      true
    end
  end
  class LoadAverageFailed < Error
  end
end
