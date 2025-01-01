# typed: true
# frozen_string_literal: true

# Allows unicorn workers to be used as Vexi actors.
# See unicorn_worker_id method in lib/github/config.rb for the definition.
module GitHub
  class VexiAppWorker
    include GitHub::VexiActor

    def initialize(app_worker_id)
      @app_worker_id = app_worker_id
      freeze
    end

    def ==(other)
      self.class == other.class && vexi_id == other.vexi_id
    end
    alias_method :eql?, :==

    def vexi_id
      "AppWorker:#{@app_worker_id}"
    end
  end
end
