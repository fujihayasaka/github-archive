# typed: false
# frozen_string_literal: true

# This class is a middle ground between Process.spawn and Progeny::Command,
# that handles getting output, error, and status from a child into variables
# for you, but also lets that child run in the background.
#
# For comparison, Process.spawn expects you to open your own pipes and read
# from them.  Progeny::Command handles the pipes and gets the child's output,
# error, and status into variables, but it can only run synchronously.
#
# Calling #out, #err, or #status will synchronously wait for the child to
# finish.  Calling #drain reads from the child's stdout and stderr but
# does not wait for it to finish.
#
# If your background task writes more than the pipe-buffer size
# (OS-dependent, but can be anywhere from 4K-64K), then you'll need to
# call BackgroundChild#drain periodically, or the child will block on its
# output pipes.
#
# Usage:
#   kid = BackgroundChild.new('command', '--arg', '--another-arg')
#   do_other_things
#   maybe_even_start_other_background_children
#   p kid.status
#   p kid.out
#   p kid.err
module GitHub
  class BackgroundChild
    def initialize(*argv)
      # Force unfrozen string to utilize << instead of + due to perf gain
      @out = +""
      @err = +""
      @out_r, out_w = IO.pipe
      @err_r, err_w = IO.pipe
      @cmd = argv.join(" ")
      @pid = Process.spawn(*argv, out: out_w, err: err_w)
    ensure
      out_w.close
      err_w.close
    end

    attr_reader :cmd
    attr_reader :pid

    def kill(sig = "TERM")
      Process.kill(sig, @pid) if @pid
    end

    def wait
      drain
      if @pid
        Process.waitpid(@pid)
        @pid = nil
        @status = $?
      end
    end

    def self.group_drain(kids)
      loop do
        rfds = kids.map { |k| [k.out_r, k.err_r] }.flatten.compact
        return if rfds.empty?
        res, _, _ = IO.select(rfds, nil, nil, nil)
        return if res.nil? || res.empty?
        kids.each do |k|
          if res.include?(k.out_r) || res.include?(k.err_r)
            k.drain(timeout: 0)
          end
        end
      end
    end

    def out
      wait
      @out
    end

    def err
      wait
      @err
    end

    def status
      wait
      @status
    end

    attr_reader :out_r, :err_r

    def drain(timeout: nil)
      loop do
        rfds = [@out_r, @err_r].compact
        #p "rfds", rfds
        return if rfds.empty?
        res, _, _ = IO.select(rfds, nil, nil, timeout)
        #p "res", res
        return if res.nil? || res.empty?
        if res.include?(@out_r)
          s = @out_r.readpartial(1024) rescue ""
          #p s
          if !s.empty?
            @out << s
          else
            @out_r.close
            @out_r = nil
          end
        end
        if res.include?(@err_r)
          s = @err_r.readpartial(1024) rescue ""
          if !s.empty?
            @err << s
          else
            @err_r.close
            @err_r = nil
          end
        end
      end
    end
  end
end
