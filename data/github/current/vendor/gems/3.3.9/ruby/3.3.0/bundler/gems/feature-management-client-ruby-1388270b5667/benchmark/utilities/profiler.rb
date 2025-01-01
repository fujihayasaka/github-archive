# frozen_string_literal: true
# typed: true

require "stackprof"
require "fileutils"

class Profiler
  def initialize(vexi)
    @vexi = vexi
  end

  def run(profiled_action_name, warmup_iterations, iterations, sampling_interval_in_microseconds, action)
    sanitized_action_name = sanitize_filename(profiled_action_name)

    warmup_iterations.times do
      action.call
    end

    # Disable GC before profiling
    GC.disable
    profile = StackProf.run(mode: :wall, raw: true, interval: sampling_interval_in_microseconds) do
      iterations.times do
        action.call
      end
    end
    # Enable GC after profiling
    GC.enable

    # Create ./prfoiles/speedscope and ./profiles/cpu directories if they do not exist
    FileUtils.mkdir_p(["./profiles/speedscope", "./profiles/cpu"])

    speedscope_dump_file = "./profiles/speedscope/#{sanitized_action_name}.json"

    File.write(speedscope_dump_file, JSON.generate(profile))
    puts "Open the following file in speedscope.app in your browser to view the flamegraph: '#{speedscope_dump_file}'\n"

    cpu_profile_dump_file = "./profiles/cpu/#{sanitized_action_name}_cpu_profile.dump"

    # Disable GC before profiling
    GC.disable
    profile = StackProf.run(mode: :cpu, out: cpu_profile_dump_file, interval: sampling_interval_in_microseconds) do
      iterations.times do
        action.call
      end
    end
    # Enable GC after profiling
    GC.enable

    puts "Run the following command to view the cpu profile: `stackprof '#{cpu_profile_dump_file}'`\n"
    puts "\n"
  end
end

def sanitize_filename(name)
  name.gsub(/[^0-9A-Za-z.\s]/, "").gsub(/\s+/, "_")
end
