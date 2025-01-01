# typed: true
# frozen_string_literal: true

require "octicons_helper"
require "allocation_sampler"

module GitHub
  class AllocationTracerMiddleware
    include OcticonsHelper

    TOKEN = GitHub::HTMLSafeString.make("<!-- ALLOCATION INFO -->")
    SUMMARY = GitHub::HTMLSafeString.make("<!-- ALLOCATION SUMMARY -->")

    TEMPLATE = ERB.new <<~eotemplate, trim_mode: "%<>"
    <table id="allocation-trace" class="width-full">
      <thead>
        <tr>
          <th>Type</th>
          <th>File</th>
          <th>Samples</th>
          <th>Percentage</th>
        </tr>
      </thead>
      <% group_by_type_and_top(trace_result.samples).each do |(type, top_frame), combined_samples| %>
        <% frame_id, line = top_frame %>
        <% frame = trace_result.frames[frame_id] %>
        <% count = combined_samples.map { |_, x, _| x }.inject(:+) %>
        <% next if (count / trace.overall_samples.to_f) < 0.01 %>
        <tr>
          <td valign="top"><%= type %></td>
          <td>
            <details>
              <summary>
                <%= location_html(frame, line) %>
              </summary>
              <div class="overflow-auto no-wrap bg-gray border rounded-2 p-2">
                <% _, trace_count, stack = combined_samples.first %>
                <h4>Most Popular Call Stack (Unique Stacks: <%= combined_samples.length %>,
                    This stack's weight:
                    <%= sprintf("%.2f", (trace_count / trace.overall_samples.to_f) * 100) %>%)
                </h4>
                <table class="width-full">
                  <% each_frame(trace, stack, 30) do |frame, line| %>
                    <tr>
                      <td valign="top">
                        <%= location_html(frame, line) %>
                      </td>
                    </tr>
                  <% end %>
                </table>
              </div>
            </details>
          </td>
          <td valign="top"><%= count %></td>
          <td valign="top">
            <strong class="tooltipped tooltipped-s"
                    aria-label="<%= count %> / <%= trace.overall_samples %> Samples">
            <%= sprintf("%.2f", (count / trace.overall_samples.to_f) * 100) %>%
            </strong>
          </td>
        </tr>
      <% end %>
    </table>
    eotemplate

    def self.enabled?
      GitHub.profiling_enabled?
    end

    def initialize(app, root, gem_dir)
      @app = app
      @root = root.to_s
      @gem_dir = gem_dir.to_s
    end

    def group_by_type_and_top(samples)
      samples.group_by do |type, _, frames|
        [type, frames.first]
      end.sort_by do |_, combined_samples|
        -combined_samples.map { |_, count, _| count }.inject(:+)
      end
    end

    def each_frame(trace, stack, max_depth)
      frames = trace.frames

      0.upto([max_depth, stack.length - 1].min) do |i|
        id, line = stack[i]
        frame = frames[id]
        yield(frame, line)
      end
    end

    # Note that we use request.GET rather than request.params throughout this
    # class because a) we only expect parameters to be passed to us through the
    # URL's query string, b) we don't want to spend time inspecting potentially
    # large POST bodies, and c) the POST bodies may be in encodings that Rack
    # doesn't expect but that our Rails app handles just fine. See
    # https://github.com/github/github/issues/31228.
    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless request.GET.has_key?("allocation_tracer")
      return @app.call(env) unless GitHub::StaffOnlyCookie.read(request.cookies)

      interval = request.GET["allocation_tracer"].to_i
      interval = interval > 0 ? interval : 1

      response = nil
      begin
        trace = ObjectSpace::AllocationSampler.new(interval: interval)
        trace.enable
        before = GC.stat :total_allocated_objects
        status, headers, body = @app.call(env)
        response = Rack::Response.new(body, status, headers)
        buffer = +""
        body.each { |chunk| buffer << chunk } # loop over the body in case something is deferred
        body.close if body.respond_to?(:close)
        allocations = GC.stat(:total_allocated_objects) - before
      ensure
        trace&.disable
      end

      return response.finish unless response.headers["Content-Type"] =~ %r|text/html|

      trace_result = trace.result
      buffer.sub!(TOKEN, TEMPLATE.result(binding))
      buffer.sub!(SUMMARY, "#{trace.overall_samples} Samples / #{allocations} Allocations")

      [status, headers, [buffer]]
    end

    private

    def location_html(frame, line)
      file = frame.path

      if !file || file == "<cfunc>"
        return "<text>#{frame.name}</text>"
      end

      location = GitHub::FormattedStackLocation.new(file, line)
      if location.linkable?
        "<a href=\"#{location.view_source_url}\" target=\"_blank\">#{location.description}</a>"
      else
        "<text>#{location.description}</text>"
      end
    end
  end
end
