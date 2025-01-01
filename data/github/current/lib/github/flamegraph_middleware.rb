# typed: true
# frozen_string_literal: true

module GitHub
  class FlamegraphMiddleware
    INTERVAL_DEFAULT = 1000
    INTERVAL_MIN = 10

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
      return @app.call(env) unless GitHub::FlamegraphMiddleware.enabled?
      return @app.call(env) unless request.GET.has_key?("flamegraph")
      return @app.call(env) unless GitHub::StaffOnlyCookie.read(request.cookies) || Rails.env.development?

      mode = :wall
      case request.GET["flamegraph_mode"]
      when "cpu"
        mode = :cpu
      when "object"
        mode = :object
      end

      if request.GET.has_key?("flamegraph_json")
        env["HTTP_ACCEPT"] = "application/json"
      end

      # Including frames where GC was executing in the profile is sometimes
      # useful but it makes flamegraphs much harder to read because it breaks
      # up method calls.  Since this is primarily a controller for flamegraphs,
      # GC frames will only be present if you ask for them.
      include_gc = request.GET["include_gc"].present?

      if request.GET["flamegraph_interval"].present?
        interval = request.GET["flamegraph_interval"].to_i
      else
        interval = INTERVAL_DEFAULT
      end
      interval = INTERVAL_MIN if interval < INTERVAL_MIN

      # Vernier: Ruby 3.2+ profiler. This doesn't share any code with the
      # stackprof collector, but we'll piggyback on the same middleware.
      if request.GET["flamegraph_mode"] == "vernier"
        status = headers = body = T.let(nil, T.untyped)
        allocation_sample_rate = request.GET["flamegraph_allocation_sample_rate"].to_i
        result = Vernier.trace(interval: interval, allocation_sample_rate: allocation_sample_rate, hooks: [:rails]) do
          status, headers, body = @app.call(env)
        end
        body = result.to_gecko

        headers["Content-Type"] = "application/json; charset=utf-8"
        filename = "#{request.path.gsub("/", "_")}_#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.vernier.json"
        headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
        headers["Content-Length"] = body&.bytesize.to_s
        status = 200

        return Rack::Response.new(body, status, headers).finish
      end

      # Reset state from last time.
      StackProf.results

      status = headers = body = T.let(nil, T.untyped)
      data = StackProf.run(raw: true, ignore_gc: !include_gc, aggregate: true, mode: mode, interval: interval) do
        status, headers, body = @app.call(env)
        body.close if body.respond_to?(:close)
      end

      out = StringIO.new
      report = StackProf::Report.new(data)

      if request.GET["flamegraph_output"] == "d3"
        report.print_d3_flamegraph(out)
        body = out.string
        headers["Content-Type"] = "text/html"
        filename = "flamegraph_#{request.path.gsub("/", "_")}_#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.html"
        headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
      elsif request.GET["flamegraph_output"] == "raw"
        report.print_dump(out)
        body = out.string
        headers["Content-Type"] = "text/binary"
        filename = "stackprof_#{request.path.gsub("/", "_")}_#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.dump"
        headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
      elsif request.GET["flamegraph_output"] == "json"
        report.print_json(out)
        body = out.string
        headers["Content-Type"] = "application/json; charset=utf-8"
        filename = "#{request.path.gsub("/", "_")}_#{DateTime.now.strftime("%Y-%m-%d-%H-%M-%S")}.stackprof.json"
        headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
      else
        report.print_timeline_flamegraph(out)
        body = out.string[11..-3]
        headers["Content-Type"] = "application/json"
      end
      # Make sure the actual response has a correct content-length instead
      # of whatever the wrapped app generated.
      headers["Content-Length"] = body&.bytesize.to_s
      # Ensure that flamegraph can be returned when status is 204 No Content
      status = status == 204 ? 200 : status
      Rack::Response.new(body, status, headers).finish
    end

    def self.enabled?
      GitHub.profiling_enabled? && defined?(StackProf)
    end
  end
end
