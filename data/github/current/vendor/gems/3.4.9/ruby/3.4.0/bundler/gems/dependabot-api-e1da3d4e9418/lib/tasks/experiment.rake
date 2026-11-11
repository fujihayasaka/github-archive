# frozen_string_literal: true

require "dependabot/experiment"

namespace :experiment do
  task :current_sample_rate, %i(name) => [:environment] do |_task, args|
    raise "Experiment name is required" unless args[:name]

    rate = Dependabot::Experiment.new(args[:name]).current_sample_rate

    puts <<-MSG
    The experiment '#{args[:name]}' is performed on #{rate}% of calls.
    MSG
  end

  task :set_sample_rate, %i(name percent) => [:environment] do |_task, args|
    raise "Experiment name is required" unless args[:name]
    raise "Percentage is required" unless args[:percent]

    percent = args[:percent].to_i

    Dependabot::Experiment.new(args[:name]).sample_rate(percent)
    rate = Dependabot::Experiment.new(args[:name]).current_sample_rate

    puts <<-MSG
    The experiment '#{args[:name]}' has been updated to #{rate}% of calls.
    MSG
  end

  task :cleanup_config, %i(name) => [:environment] do |_task, args|
    raise "Experiment name is required" unless args[:name]

    Dependabot::Experiment.new(args[:name]).cleanup

    puts <<-MSG
    The experiment '#{args[:name]}' configuration has been cleaned up.

    Any mismatch data remains in redis, use 'cleanup_all' to remove this as well.
    MSG
  end

  task :cleanup_all, %i(name) => [:environment] do |_task, args|
    raise "Experiment name is required" unless args[:name]

    Dependabot::Experiment.new(args[:name]).cleanup!

    puts <<-MSG
    The experiment '#{args[:name]}' has been cleaned up, including mismatch data.
    MSG
  end
end
