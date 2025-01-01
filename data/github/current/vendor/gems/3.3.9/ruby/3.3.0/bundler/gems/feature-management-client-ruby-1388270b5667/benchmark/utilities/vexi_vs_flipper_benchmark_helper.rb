# frozen_string_literal: true
# typed: true

class VexiVersusFlipperBenchmarkHelper
  def initialize(vexi, flipper)
    @vexi = vexi
    @flipper = flipper
  end

  def run(name, flag, actors = [], gc_suite = nil)
    print "Running benchmark: #{name}."
    print " With Garbage collection disabled." if gc_suite
    print "\n"
    Benchmark.ips do |x|
      x.config(suite: gc_suite) if gc_suite
      x.config(warmup: 0.5, time: 2)
      x.report("vexi.enabled?") { @vexi.enabled?(flag, actors) }
      x.report("flipper.enabled?") { @flipper.enabled?(flag, actors) }
      x.compare!
    end

    print "\n"
  end
end
