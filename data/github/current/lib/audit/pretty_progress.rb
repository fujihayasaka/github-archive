# typed: true
# frozen_string_literal: true

module Audit
  class PrettyProgress
    # Text color is yellow
    DOTS = [
      "\u001b[33m\u280b\u001b[0m", # ⠋
      "\u001b[33m\u2819\u001b[0m", # ⠙
      "\u001b[33m\u2839\u001b[0m", # ⠹
      "\u001b[33m\u2838\u001b[0m", # ⠸
      "\u001b[33m\u283c\u001b[0m", # ⠼
      "\u001b[33m\u2834\u001b[0m", # ⠴
      "\u001b[33m\u2826\u001b[0m", # ⠦
      "\u001b[33m\u2827\u001b[0m", # ⠧
      "\u001b[33m\u2807\u001b[0m", # ⠇
      "\u001b[33m\u280f\u001b[0m", # ⠏
    ]
    CHECKMARK = "\u001b[32m\u2713\u001b[0m"

    def initialize(timestamp_prefix: false)
      @timestamp_prefix = !!timestamp_prefix
      reset
    end

    def step(msg, counter: nil)
      # Need to set for when we first start displaying a message
      start_time

      message(msg, counter: counter) do |line|
        flush, prefix = dot
        line = "#{prefix} #{line}\r"
        print line unless Rails.env.test?
        $stdout.flush if flush
      end
    end

    def start_time
      @start_time ||= Time.now
    end

    def done(msg, counter: nil)
      # Need to keep track of the old message length when overwriting a line with
      # carriage return otherwise you could end up with overflow.
      old_length = @message&.length || 0

      # Print out how long this section took.
      took = Time.now - start_time
      duration = ActiveSupport::Duration.build(took.round(1)).inspect
      msg = "#{msg} ... took #{duration}"

      message(msg, counter: counter) do |line|
        timestamp_prefix = "[#{Time.now.strftime("%Y-%m-%dT%H:%M:%S")}] " if @timestamp_prefix
        line = "#{timestamp_prefix}#{CHECKMARK} #{line}".ljust(old_length)
        puts line unless Rails.env.test?
      end

      reset
    end

    private

    def reset
      @start_time = nil
      @last_dot_frame = nil
      @frame = 0
      @counter = 0
    end

    # Private: Keeps a running counter of every time this is invocated to
    # properly cycle through all the frames in a steady framerate.
    #
    # Every 100ms it will reset the last time a new frame was rendered. We store
    # this to steadily render each frame, otherwise if the script does 100,000
    # invocations in 1 second it'll cycle through 100,000 times and thats way
    # too fast.
    #
    # Returns [Boolean, String]
    def dot
      flush = false
      @last_dot_frame ||= start_time
      time = (Time.now - @last_dot_frame)

      # Every 100ms render the next frame. Since there are 10 frames we want to
      # render the full circle in 1 second.
      if time >= 0.1
        @last_dot_frame = Time.now
        flush = true

        # Need to restart the animation when it reaches the end
        @frame += 1

        if @frame == DOTS.length
          @frame = 0
        end
      end

      [flush, DOTS[@frame]]
    end

    def message(msg, counter: nil, &block)
      # Conditionally format the message
      @message = if counter.nil?
        msg
      else
        prefix = ActiveSupport::NumberHelper.number_to_delimited(counter)
        "#{prefix} #{msg}"
      end

      block.call(@message)
    end
  end
end
