# frozen_string_literal: true
# typed: true

require "sorbet-runtime"

# Disable sorbet runtime checks
T::Configuration.default_checked_level = :never

require "vexi"
require_relative "../utilities/benchmark_actor"
require_relative "../utilities/profiler"

Vexi.configure do |builder|
  builder.adapter.in_memory(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)
end

vexi = Vexi.instance

profiler = Profiler.new(vexi)

puts "\nRunning profiler for vexi with in memory adapter only:\n\n"

# Vexi enabled? for a flag that does not exist without passing an actor.
profiler.run("Comparing vexi enabled? with flipper.enabled? for a flag that does not exist without passing an actor", 100, 1000, 100, -> {
  vexi.enabled?("non_existent_flag")
})

# Vexi enabled? for a flag that does not exist with passing an actor.
actor = BenchmarkActor.new
profiler.run("Comparing vexi enabled? with flipper.enabled? for a flag that does not exist with passing an actor", 100, 1000, 100, -> {
  vexi.enabled?("non_existent_flag", actor)
})

puts "------------------------------------------------------\n"
