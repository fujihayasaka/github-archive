# typed: true
# frozen_string_literal: true

require "get_process_mem"

module GitHub
  module Memory
    def self.memrss
      GetProcessMem.new.bytes
    end

    MAPPING = /^(Rss|Shared|Private).*:\s+(\d+)/

    def self.usage(pid = Process.pid)
      usage_linux("/proc/#{pid}/smaps_rollup")
    end

    def self.usage_linux(file)
      mem = { "Rss" => 0, "Shared" => 0, "Private" => 0 }
      File.read(file).scan(MAPPING) do |type, n|
        mem[type] += n.to_i
      end

      Usage.new(
        success: true,
        rss: mem["Rss"] * 1.kilobyte,
        shared: mem["Shared"] * 1.kilobyte,
        priv: mem["Private"] * 1.kilobyte
      )
    rescue Errno::ENOENT, Errno::EACCES
      Usage.new(success: false, rss: 0, shared: 0, priv: 0)
    end

    # Only do RSS, shared / private would be possible with vmmap but
    # that's probably overkill for the basics here to verify functionality
    def self.usage_memrss_only
      Usage.new(
        success: true,
        rss: memrss,
        shared: 0,
        priv: 0
      )
    end

    class Usage
      attr_reader :rss, :shared, :priv

      def initialize(success:, rss:, shared:, priv:)
        @success = success
        @rss = rss
        @shared = shared
        @priv = priv
      end

      def success?
        @success
      end

      def delta(other)
        unless success? && other.success?
          return Usage.new(success: false, rss: 0, shared: 0, priv: 0)
        end

        Usage.new(
          success: true,
          rss: rss - other.rss,
          shared: shared - other.shared,
          priv: priv - other.priv
        )
      end
    end
  end
end
