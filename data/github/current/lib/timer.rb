# typed: true
# frozen_string_literal: true

# A utility class for measuring durations.
class Timer
  attr_reader :started_at

  # Public: Create and start a timer.
  #
  # @param cpu [Boolean] when true also captures process and thread CPU time
  #   (default: false). Only pass true when you actually need
  #   elapsed_cpu_ms / elapsed_idle_ms / elapsed_thread_cpu_ms.
  #
  # Returns a Timer.
  def self.start(cpu: false)
    new(cpu: cpu).tap(&:start)
  end

  def initialize(cpu: false)
    @track_cpu = cpu
  end

  # Public: Start the timer. Can be called repeatedly to reset the timer.
  #
  # Returns nothing.
  def start
    @started_at = Time.now
    @start_mono = now
    @finish_mono = nil
    if @track_cpu
      @start_cputime = cputime
      @start_thread_cputime = thread_cputime
      @finish_cputime = nil
      @finish_thread_cputime = nil
    end
  end

  # Public: Stop the timer.
  #
  # Returns nothing.
  def stop
    @finish_mono ||= now
    if @track_cpu
      @finish_cputime ||= cputime
      @finish_thread_cputime ||= thread_cputime
    end
    @started_at = nil
  end

  def started?
    @started_at != nil
  end

  # Public: Measure the elapsed milliseconds since the timer started. Implicitly
  # stops the timer.
  #
  # Returns an Integer.
  def elapsed_ms(precision = 0)
    stop

    ((@finish_mono - @start_mono) * 1000).round(precision)
  end

  # Public: Measure the elapsed milliseconds spent on CPU since the timer
  # started. Implicitly stops the timer.
  #
  # Returns an Integer.
  def elapsed_cpu_ms(precision = 0)
    stop

    ((@finish_cputime - @start_cputime) * 1000).ceil(precision)
  end

  # Public: Measure the elapsed milliseconds *not* spent on CPU since the timer
  # started. Implicitly stops the timer.
  #
  # Returns an Integer.
  def elapsed_idle_ms(precision = 0)
    stop

    [elapsed_ms(precision) - elapsed_cpu_ms(precision), 0].max
  end

  # Public: Measure the elapsed milliseconds spent on the current thread on CPU
  # since the timer started. Implicitly stops the timer.
  #
  # Returns an Integer.
  def elapsed_thread_cpu_ms(precision = 0)
    stop

    ((@finish_thread_cputime - @start_thread_cputime) * 1000).ceil(precision)
  end

  private

  def cputime
    Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
  end

  def thread_cputime
    Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
