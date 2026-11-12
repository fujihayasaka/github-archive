class Daemon
  attr_accessor :stop_proc

  def self.run(script, **opts, &block)
    new.run(script, **opts, &block)
  end

  def initialize
    # do nothing when stopping
    @stop_proc = -> {}
  end

  def run(script, parallelism: 1, ontop: false, &block)
    @ontop = ontop
    parallelism.times do |i|
      Daemons.run_proc("#{script}_#{i+1}", options) do
        DependencyGraph.logger.info("Starting script instance",
          "gh.dependency_graph.daemon.script" => script,
          "gh.dependency_graph.daemon.instance" => i+1,
        )

        Rails.application.post_daemonization_hook

        block.call(DependencyGraph.logger, self)
      end
    end
  end

  def log_file
    env = ENV["RAILS_ENV"] || "development"
    Pathname.new(File.expand_path("../../../log/#{env}.log", __FILE__))
  end

  def options
    {
     monitor:              true,
     multiple:             false, # we run multiple by spawning deamons with different names
     log_output:           true,
     log_dir:              log_file.dirname,
     output_logfilename:   log_file.basename,
     force_kill_waittime:  30,
     ontop:                @ontop,
     stop_proc:           -> { stop_proc.call } # we need to wrap it in a lambda since this is loaded at initialization by Daemons, and we may change it from within the daemon
   }
  end

  def before_stopping(&block)
    @stop_proc = block
  end
end
