# typed: true
# frozen_string_literal: true

class Issue::Loader::Base
  include Issue::PrefillHelper
  # Load does all the heavy data lifting (loading models from AR, gitrpc, etc.)
  # see app/models/issue/loader/labels.rb for example usage
  def load
    raise NotImplementedError
  end

  # Takes an instance of a loader and calls load with timing instrumentation
  # see app/models/issue/loader/labels.rb for example usage
  def self.load_for(loader)
    loader.track_execution_time do
      loader.load
    end
  end

  # scope is an optional string for disambiguating multiple calls to the same loader/preloader method
  def track_execution_time(scope = nil)
    result = T.let(nil, T.untyped)
    timer = T.let(nil, T.nilable(Timer))

    klass = T.must(self.class.name).demodulize.downcase
    method = T.must(T.must(caller_locations(1, 1))[0]).base_label
    method = "#{method}.#{scope}" if scope
    span_name = "issue_loader::#{klass}::#{method}"
    mysql_count_start = GitHub::MysqlInstrumenter.query_count

    GitHub.tracer.in_span(span_name, kind: :internal) do |span|
      timer = Timer.start
      result = yield
      timer.stop

      mysql_count = GitHub::MysqlInstrumenter.query_count
      span.set_attribute("mysql_queries", mysql_count - mysql_count_start)
    end

    GitHub.dogstats.distribution("issue_loader.dist.time", T.must(timer).elapsed_ms, tags: [
      "fn:#{klass}:#{method}"
    ])

    result
  end
end
