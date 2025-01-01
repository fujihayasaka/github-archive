# typed: true
# frozen_string_literal: true

module TraceRenderer
  class MermaidTrace
    def self.render(trace_id, diagram_type: "gantt", scope: "default")
      trace = DatadogClient.get_trace(trace_id)
      return if trace.nil?

      spans = trace["data"]["attributes"]["trace"]["spans"]
      root_span_id = trace["data"]["attributes"]["trace"]["root_id"]
      root_span = spans[root_span_id.to_s]
      root_start_time = root_span["start"]
      root_span_duration = root_span["duration"]

      if diagram_type == "flowchart"
        mark_service_entry_spans!(spans, root_span_id)
        if scope == "service_entries"
          spans_as_service_entries = map_spans_as_service_entries(spans, root_span_id)
          format_mermaid_as_flowchart_service_entries(trace_id, spans, spans_as_service_entries, root_span_duration)
        else
          spans_as_unique_services = map_spans_as_unique_services(spans, root_span_id)
          format_mermaid_as_flowchart_unique_services(trace_id, spans, spans_as_unique_services, root_span_duration)
        end
      else
        span_times = recurse_span_details(spans, root_span_id, root_start_time)
        format_mermaid_as_gantt(trace_id, span_times)
      end
    end

    def self.format_mermaid_as_gantt(trace_id, span_times)
      span_text = String.new("")
      span_times.each do |name, spans|
        span_text << "\tsection #{name}\n"
        spans.each do |span|
          span_text << span << "\n"
        end
        span_text << "\n"
      end

      output_string = <<~HEREDOC
      ```mermaid
      gantt
      \t title Flamegraph for Trace ID: #{trace_id}
      \t dateFormat x
      \t axisFormat %S.%L

      #{span_text}
      ```
      HEREDOC
      output_string
    end

    def self.recurse_span_details(spans, parent_span_id, root_start_time, span_times =  Hash.new { |h, k| h[k] = [] })
      span = spans[parent_span_id.to_s]
      return span_times unless span

      start_time = ((span["start"] - root_start_time) * 1000000).round
      duration = ((span["end"] - span["start"]) * 1000000).round

      name = "#{span['name']}/#{span['service']}"
      span_times[name.to_s].push "\t#{span['resource']}         :#{start_time}, #{duration}"

      span["children_ids"].each do |child_id|
        recurse_span_details(spans, child_id, root_start_time, span_times)
      end
      span_times
    end

    def self.format_mermaid_as_flowchart_unique_services(trace_id, spans, unique_services_map, root_span_duration)
      span_text = String.new("")
      grouped_by_service_id = spans.group_by { |_, span_attrs| get_service_id_for(span_attrs) }

      grouped_by_service_id.each do |service_id, spans_for_service|
        service_span = spans_for_service[0][1]
        span_text << get_mermaid_line_for(service_span)
        dependencies = unique_services_map[service_id]

        dependencies.uniq.each do |dep_service_id|
          dep_service_span = grouped_by_service_id[dep_service_id][0][1]
          span_text << "\t #{service_id} ----> #{dep_service_id} \n"
        end
      end

      output_string = <<~HEREDOC
      ```mermaid
      flowchart LR
      \t title[Flowchart for Trace ID: #{trace_id} <br> #{(root_span_duration * 1000).round} ms] \n
      click title "https://app.datadoghq.com/apm/trace/#{trace_id}" _blank

      #{span_text}
      ```
      HEREDOC
      output_string
    end

    def self.map_spans_as_unique_services(spans, parent_span_id)
      unique_services_map = Hash.new { |h, k| h[k] = [] }
      spans.each do |_, span_attrs|
        if span_attrs["_is_service_entry"]
          parent_service_id = get_service_id_for(span_attrs)
          map_to_next_dependency(spans, span_attrs["children_ids"], parent_service_id, unique_services_map)
        end
      end
      unique_services_map
    end

    def self.map_to_next_dependency(spans, children_ids, parent_service_id, unique_services_map)
      return if children_ids.empty?

      service_entry_spans, not_service_entry_spans = children_ids.partition { |child_span_id| spans[child_span_id]["_is_service_entry"] == true }
      service_entries_as_service_ids = service_entry_spans.map { |id| get_service_id_for(spans[id]) }
      unique_services_map[parent_service_id] += service_entries_as_service_ids
      next_children = not_service_entry_spans.map { |span_id| spans[span_id]["children_ids"] }.flatten.uniq
      map_to_next_dependency(spans, next_children, parent_service_id, unique_services_map)
    end

    def self.format_mermaid_as_flowchart_service_entries(trace_id, spans, service_entries_map, root_span_duration)
      span_text = String.new("")

      spans.each do |span_id, span_attrs|
        next unless span_attrs["_is_service_entry"]
        span_text << get_mermaid_line_for(span_attrs, scope: "service_entries")
        service_entry_descendant_ids = service_entries_map[span_id]

        service_entry_descendant_ids.each do |service_entry_descendant_id|
          service_entry_descendant = spans[service_entry_descendant_id]
          if service_entry_descendant["type"] == "db"
            link_text = get_link_text_for(service_entry_descendant)
          else
            link_text = get_link_text_for(span_attrs)
          end
          span_text << "\t #{span_id} #{link_text} #{service_entry_descendant_id} \n"
        end
      end

      output_string = <<~HEREDOC
      ```mermaid
      flowchart LR
      \t title[Flamegraph for Trace ID: #{trace_id} <br> #{(root_span_duration * 1000).round} ms] \n
      click title "https://app.datadoghq.com/apm/trace/#{trace_id}" _blank

      #{span_text}
      ```
      HEREDOC
      output_string
    end

    def self.map_spans_as_service_entries(spans, parent_span_id)
      service_entries_map = Hash.new { |h, k| h[k] = [] }
      spans.each do |span_id, span_attrs|
        if span_attrs["_is_service_entry"]
          map_to_next_service_entry_descendant(spans, span_attrs["children_ids"], span_id, service_entries_map)
        end
      end
      service_entries_map
    end

    def self.map_to_next_service_entry_descendant(spans, children_ids, parent_id, service_entries_map)
      return if children_ids.empty?

      service_entry_spans, not_service_entry_spans = children_ids.partition { |child_span_id| spans[child_span_id]["_is_service_entry"] == true }
      service_entries_map[parent_id] += service_entry_spans
      next_children = not_service_entry_spans.map { |span_id| spans[span_id]["children_ids"] }.flatten.uniq
      map_to_next_service_entry_descendant(spans, next_children, parent_id, service_entries_map)
    end

    def self.mark_service_entry_spans!(spans, current_span_id)
      current_span = spans[current_span_id]
      return unless current_span

      parent_span = spans[current_span["parent_id"]]
      if !parent_span || parent_span["type"] != current_span["type"] || parent_span["service"] != current_span["service"] || parent_span["name"] != current_span["name"]
        current_span["_is_service_entry"] = true
      end

      current_span["children_ids"].each do |child_id|
        mark_service_entry_spans!(spans, child_id)
      end
    end

    SPAN_TYPE_TO_COLOR = {
      "db" => "#ffcc00",
      "web" => "#bed017",
      "http" => "#cc3c71",
    }

    def self.get_mermaid_line_for(attrs, scope: "default")
      node_id = scope == "service_entries" ? attrs["span_id"] : get_service_id_for(attrs)
      label = get_label_for(attrs, scope: scope)
      style = get_style_for(attrs, node_id)

      if attrs["type"] == "db"
        "\t #{node_id}[(#{label})] \n #{style} \n"
      else
        "\t #{node_id}[#{label}] \n #{style} \n"
      end
    end

    def self.get_label_for(span_attrs, scope: "default")
      if span_attrs["type"] == "db"
        "\"#{span_attrs["meta"]["peer.service"]}\""
      elsif scope == "service_entries"
        "\"#{span_attrs['name']}/#{span_attrs['service']} <br> #{span_attrs["resource"]}\""
      else
        "#{span_attrs["service"]}/#{span_attrs["name"]}"
      end
    end

    def self.get_link_text_for(span_attrs)
      if span_attrs["type"] == "db" || span_attrs["type"] == "http"
        "--#{span_attrs["resource"]}-->"
      else
        "---->"
      end
    end

    def self.get_service_id_for(span_attrs)
      if span_attrs["type"] == "db"
        span_attrs["meta"]["peer.service"]
      else
        "#{span_attrs["type"]}/#{span_attrs["service"]}/#{span_attrs["name"]}"
      end
    end

    def self.get_style_for(attrs, node_id)
      fill = SPAN_TYPE_TO_COLOR[attrs["type"]]
      "\t\t style #{node_id} fill:#{fill},color:#1f2020,stroke:#1f2020,stroke-width:4px" if fill
    end
  end
end
