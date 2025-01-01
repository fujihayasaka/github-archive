require "ruby-prof"

# Opt into this middleware by calling your favorite API endpoints with ?trace_profiler
module DependencyGraph
  class TraceProfilerMiddleware
    def initialize(app)
      @app = app
    end

    # Note that we use request.GET rather than request.params throughout this
    # class because a) we only expect parameters to be passed to us through the
    # URL's query string, b) we don't want to spend time inspecting potentially
    # large POST bodies, and c) the POST bodies may be in encodings that Rack
    # doesn't expect but that our Rails app handles just fine. See
    # https://github.com/github/github/issues/31228.
    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless request.GET.has_key?("trace_profiler")

      status = headers = body = nil

      if request.GET.has_key?("trace_profiler_allocations")
        RubyProf.measure_mode = RubyProf::ALLOCATIONS
      elsif request.GET.has_key?("trace_profiler_process_time")
        RubyProf.measure_mode = RubyProf::PROCESS_TIME
      end

      if request.GET.has_key?("trace_profiler_output_graph")
        printerFactory = -> (result) { RubyProf::GraphPrinter.new(result) }
      elsif request.GET.has_key?("trace_profiler_output_html")
        printerFactory = -> (result) { RubyProf::GraphHtmlPrinter.new(result) }
      elsif request.GET.has_key?("trace_profiler_output_callstack")
        printerFactory = -> (result) { RubyProf::CallStackPrinter.new(result) }
      elsif request.GET.has_key?("trace_profiler_output_calltree")
        printerFactory = -> (result) { RubyProf::CallTreePrinter.new(result) }
      elsif request.GET.has_key?("trace_profiler_output_dot")
        printerFactory = -> (result) { RubyProf::DotPrinter.new(result) }
      else
        printerFactory = -> (result) { RubyProf::FlatPrinter.new(result) }
      end

      # query strings break twirp routing
      env["QUERY_STRING"] = "" if env["PATH_INFO"].starts_with?("/twirp/")

      result = RubyProf.profile do
        status, headers, body = @app.call(env)
        body.close if body.respond_to?(:close)
      end

      printer = printerFactory.call(result)
      printerCapture = StringIO.new
      printer.print(printerCapture, min_percent: 1)

      body = printerCapture.string
      headers["Content-Type"] = "application/text"
      # Make sure the actual response has a correct content-length instead
      # of whatever the wrapped app generated.
      headers["Content-Length"] = body.bytesize.to_s
      status = 200
      Rack::Response.new(body, status, headers).finish
    end
  end
end
