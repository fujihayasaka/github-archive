# typed: true
# frozen_string_literal: true

module GitHub
  class LineProfilerMiddleware
    def self.enabled?
      GitHub.profiling_enabled? && defined?(lineprof)
    end

    def initialize(app, root)
      @app = app
      @root = root
    end

    # Note that we use request.GET rather than request.params throughout this
    # class because a) we only expect parameters to be passed to us through the
    # URL's query string, b) we don't want to spend time inspecting potentially
    # large POST bodies, and c) the POST bodies may be in encodings that Rack
    # doesn't expect but that our Rails app handles just fine. See
    # https://github.com/github/github/issues/31228.
    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless GitHub::LineProfilerMiddleware.enabled?
      return @app.call(env) unless request.GET.has_key?("lineprofiler")
      return @app.call(env) unless GitHub::StaffOnlyCookie.read(request.cookies)

      response = T.let(nil, T.nilable(Rack::Response))
      profile = lineprof(regex(request)) do
        status, headers, body = @app.call(env)
        response = Rack::Response.new(body, status, headers)
        body.close if body.respond_to?(:close)
      end
      response = T.cast(response, Rack::Response)
      return response.finish unless response.headers["Content-Type"] =~ %r|text/html|

      sort = request.GET["lineprofiler_sort"]
      mode = request.GET["lineprofiler_mode"]
      min  = (request.GET["lineprofiler_min"] || 5).to_i * 1000
      summary = request.GET["lineprofiler_summary"]

      per_file = profile.map do |file, lines|
        total, child, excl, total_cpu, child_cpu, excl_cpu = lines[0]

        wall = summary == "exclusive" ? excl : total
        cpu  = summary == "exclusive" ? excl_cpu : total_cpu
        idle = summary == "exclusive" ? (excl - excl_cpu) : (total - total_cpu)

        [
          file, lines,
          wall, cpu, idle,
          if sort == "idle"
            idle
          else
            sort == "cpu" ? cpu : wall
          end
        ]
      end.sort_by { |_a, _b, _c, _d, _e, f| -f }

      output = +""
      if mode == "cpu"
        output << "  CPU TIME +  IDLE TIME   FILE\n"
      else
        output << "      TIME   FILE\n"
      end

      per_file.each do |file_name, lines, file_wall, file_cpu, file_idle, file_sort|
        show_src = file_sort > min
        tmpl = show_src ? "<details class=\"d-inline-block v-align-top\"><summary>%s</summary>" : "%s"

        if mode == "cpu"
          output << sprintf("% 8.1fms + % 8.1fms   #{tmpl}\n", file_cpu / 1000.0, file_idle / 1000.0, file_name.sub("#{@root}/", ""))
        else
          output << sprintf("% 8.1fms   #{tmpl}\n", file_wall / 1000.0, file_name.sub("#{@root}/", ""))
        end

        next unless show_src

        output << "<div>"
        File.readlines(file_name).each_with_index do |line, i|
          wall, cpu, calls = lines[i + 1]

          if calls && calls > 0
            if mode == "cpu"
              idle = wall - cpu
              output << sprintf("% 8.1fms + % 8.1fms (% 5d) | %s", cpu / 1000.0, idle / 1000.0, calls, ERB::Util.force_escape(line))
            else
              output << sprintf("% 8.1fms (% 5d) | %s", wall / 1000.0, calls, ERB::Util.force_escape(line))
            end
          else
            if mode == "cpu"
              output << sprintf("                                | %s", ERB::Util.force_escape(line))
            else
              output << sprintf("                   | %s", ERB::Util.force_escape(line))
            end
          end
        end
        output << "</div></details>\n"
      end

      response.write("<template id='line-profile'><pre>#{output}</pre></template>")

      response.finish
    end

    private

    def regex(request)
      case request.GET["lineprofiler"]
      when "app"
        %r{\A#{Regexp.escape(@root.to_s)}(?:/packages/[^/]+)?/(app|lib)}o
      when "views"
        %r{\A#{Regexp.escape(@root.to_s)}(?:/packages/[^/]+)?/app/view}
      when "gems"
        %r|\A#{Regexp.escape(@root.to_s)}/vendor/gems|
      when "all"
        %r|\A#{Regexp.escape(@root.to_s)}|
      when "stdlib"
        %r|\A#{Regexp.escape RbConfig::CONFIG["rubylibdir"]}|
      else
        %r{\A#{Regexp.escape(@root.to_s)}(?:/packages/[^/]+)?/(app|config|initializers|lib|vendor/plugin)}
      end
    end
  end
end
