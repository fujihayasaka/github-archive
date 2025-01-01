#!/usr/bin/env ruby
# frozen_string_literal: true

# This script continuously samples CPU and memory,
# and renders three ASCII charts sequentially when a termination signal is received.
#
#   - CPU chart: sampled from /proc/stat using standard utilization formula.
#   - Memory chart: computed from /proc/meminfo using (total - available) / total.
#     on primary block devices and plotting the delta per second, normalized to the maximum observed rate.
#   - Disk IO chart: sampled from /proc/diskstats using the delta of the total time spent doing I/Os in milliseconds,
#
# The charts are rendered sequentially upon receiving SIGTERM or SIGINT signals.

require "thread"

class PerfCharts
  # Symbol used to render the line
  CHART_SYMBOL    = "█" # Symbol used to render the line
  CHART_HEIGHT    = 11  # Vertical resolution for charts
  SAMPLE_INTERVAL = 10  # Seconds between samples

  GREEN = "\e[32m"
  YELLOW = "\e[33m"
  RED = "\e[31m"

  # Global arrays to store utilization samples.
  $cpu_samples = []
  $mem_samples = []
  $io_samples = []

  # For IO, store the previous aggregated count.
  $prev_io_total = nil

  # Reads and parses CPU stats from /proc/stat.
  def read_cpu_stats
    cpu_line = File.readlines("/proc/stat").find { |line| line.start_with?("cpu ") }
    fields = cpu_line.split
    {
      user:     fields[1].to_i,
      nice:     fields[2].to_i,
      system:   fields[3].to_i,
      idle:     fields[4].to_i,
      iowait:   fields[5].to_i,
      irq:      fields[6].to_i,
      softirq:  fields[7].to_i,
      steal:    fields[8].to_i
    }
  end

  # Computes CPU utilization percentage between two CPU stats readings.
  def compute_cpu_utilization(prev, curr)
    prev_idle   = prev[:idle] + prev[:iowait]
    curr_idle   = curr[:idle] + curr[:iowait]
    prev_total  = prev.values.sum
    curr_total  = curr.values.sum
    total_delta = curr_total - prev_total
    idle_delta  = curr_idle - prev_idle
    return 0 if total_delta == 0
    ((total_delta - idle_delta).to_f / total_delta * 100)
  end

  # Reads memory info from /proc/meminfo and computes memory utilization percentage.
  def read_memory_utilization
    meminfo = {}
    File.readlines("/proc/meminfo").each do |line|
      key, value, _unit = line.split
      meminfo[key.chomp(":")] = value.to_i
    end
    total = meminfo["MemTotal"]
    available = meminfo["MemAvailable"]
    used = total - available
    (used.to_f / total * 100)
  end

  def read_io_utilization
    io_total = File.readlines("/proc/diskstats").map do |line|
      fields = line.split
      next unless fields.size >= 13 && fields[2] =~ /\A[sh]d[a-z]\z/  # Process only valid disk devices with complete fields
      # puts line  # Uncomment for debugging if needed
      # Time spent doing I/Os (ms): Time spent doing I/Os in milliseconds.
      fields[12].to_i
    end.compact.sum

    $prev_io_total = io_total if $prev_io_total.nil?
    delta = io_total - $prev_io_total
    $prev_io_total = io_total
    # puts delta.to_s  # Uncomment for debugging if needed
    delta
  end

  # Format time in seconds to a label such as "30s", "1m", "1.5m".
  def format_time(seconds)
    if seconds < 60
      "#{seconds}s"
    else
      minutes = seconds / 60.0
      (minutes % 1).zero? ? "#{minutes.to_i}m" : "#{minutes.round(1)}m"
    end
  end

  # Generic method to render an ASCII chart given sample data and a title.
  def render_chart(samples, title, normalize)
    num_samples = samples.size
    grid = Array.new(CHART_HEIGHT) { Array.new(num_samples, " ") }

    # Normalize sample values relative to maximum observed value.
    max_value = samples.max
    max_value = 1 if max_value.zero?

    samples.each_with_index do |value, col|
      # Scaling: value 100% or max_value maps to top row, value 0 to bottom.
      normalized = if normalize
        100.0 * value / max_value
      else
        value
      end
      row_index = ((100 - normalized) / 100 * (CHART_HEIGHT - 1)).round
      color = if normalized < 50
        GREEN
      elsif normalized < 90
        YELLOW
      else
        RED
      end
      grid[row_index][col] = color + CHART_SYMBOL + "\e[0m"
    end

    puts "\n#{title}"
    grid.each_with_index do |row, i|
      percentage_label = (100 - (i.to_f / (CHART_HEIGHT - 1) * 100)).round.to_s.rjust(3)
      puts "#{percentage_label}% |#{row.join}"
    end

    puts "     +#{'-' * num_samples}"
    tick_line = Array.new(num_samples, " ")
    samples.size.times do |i|
      tick_line[i] = "|" if i % 6 == 0  # Tick mark every 6 samples (60 seconds)
    end
    puts "      #{tick_line.join}"

    label_line = Array.new(num_samples, " ")
    samples.size.times do |i|
      if i % 6 == 0
        label = format_time(i * SAMPLE_INTERVAL)
        label.chars.each_with_index do |char, offset|
          pos = i + offset
          break if pos >= num_samples
          label_line[pos] = char
        end
      end
    end
    puts "      #{label_line.join}"
  end

  # Render the charts sequentially.
  def render_all_charts
    puts "\nRendering CPU/Mem/IO utilization charts from #{$cpu_samples.size} samples, every #{SAMPLE_INTERVAL} seconds."

    render_chart($cpu_samples, "CPU", false)
    render_chart($mem_samples, "Memory", false)
    render_chart($io_samples, "Disk IO", true)
  end

  # Set up a mutex to allow safe access to samples if needed.
  $samples_mutex = Mutex.new

  # Signal handler to render charts before termination.
  def setup_signal_handlers
    puts "Starting CPU/Mem/IO utilization sampling every #{SAMPLE_INTERVAL}s.. Rendering of the charts will be done when the process will stop (Press Ctrl+C to stop now)."

    Signal.trap("TERM") do
      render_all_charts
      exit
    end

    Signal.trap("INT") do
      render_all_charts
      exit
    end
  end

  # Main sampling loop.
  def main_loop
    setup_signal_handlers

    # Initial CPU stats sample.
    prev_cpu_stats = read_cpu_stats

    loop do
      sleep SAMPLE_INTERVAL

      # CPU utilization
      curr_cpu_stats = read_cpu_stats
      cpu_util = compute_cpu_utilization(prev_cpu_stats, curr_cpu_stats)
      $samples_mutex.synchronize { $cpu_samples << cpu_util }
      prev_cpu_stats = curr_cpu_stats

      # Memory utilization
      $samples_mutex.synchronize { $mem_samples << read_memory_utilization }

      # IO
      $samples_mutex.synchronize { $io_samples << read_io_utilization }
    end
  end
end

# Start the main sampling loop.
PerfCharts.new.main_loop
