# typed: true
# frozen_string_literal: true

# A utility class for measuring durations.
class Timer
  attr_reader :started_at

  # Public: Create and start a timer.
  #
  # Returns a Timer.
  def self.start
    new.tap(&:start)
  end

  # Public: Start the timer. Can be called repeatedly to reset the timer.
  #
  # Returns nothing.
  def start
    @started_at = Time.now
    @start_mono = now
    @start_cputime = cputime
    @start_thread_cputime = thread_cputime
  end

  # Public: Stop the timer.
  #
  # Returns nothing.
  def stop
    @finish_mono ||= now
    @finish_cputime ||= cputime
    @finish_thread_cputime ||= thread_cputime
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
