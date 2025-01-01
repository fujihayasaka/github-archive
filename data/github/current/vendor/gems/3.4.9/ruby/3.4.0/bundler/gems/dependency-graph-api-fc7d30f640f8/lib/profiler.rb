# frozen_string_literal: true

require "fileutils"
require "stackprof"

module Profiler
  # Profiles a block and saves a flamegraph to an HTML file
  def self.run(name:, &block)
    output_directory = File.join(Rails.root, "tmp/flame_graph", name)
    filename = File.join(output_directory, "#{Time.now.strftime('%Y-%m-%d-%H%M%S')}.html")
    FileUtils.mkdir_p(output_directory)

    results = StackProf.run(raw: true, &block)
    report = StackProf::Report.new(results)
    File.open(filename, "w") do |f|
      report.print_d3_flamegraph(f)
    end

    puts filename
  end
end
