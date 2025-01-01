# typed: true
# frozen_string_literal: true

module GitHub
  module CPU
    #
    # These values are documented here:
    #
    #     https://www.kernel.org/doc/Documentation/scheduler/sched-bwc.txt
    #
    def self.cpu_throttled_stats
      return nil if GitHub.cpu_stat_file.nil? || GitHub.cpu_stat_file.empty?
      begin
        cpu_stat_output = File.open(GitHub.cpu_stat_file) { |f| f.sysread(512) }
        _, nr_periods, _, nr_throttled, _, throttled_time_ns = cpu_stat_output.gsub("\n", " ").split(" ", 6)
        [nr_periods.to_i, nr_throttled.to_i, throttled_time_ns.to_i]
      rescue Errno::EPERM, Errno::ENOENT, EOFError, SystemCallError => e
        nil
      end
    end
  end
end
