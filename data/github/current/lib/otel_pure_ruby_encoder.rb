# typed: true
# frozen_string_literal: true

module OpenTelemetry
  module Proto
    # Pure Ruby encoder for OTLP Trace Service Protocol Buffers
    # Implements just enough of the Protobuf spec to encode trace data
    module SimpleEncoder
      module Trace
        # Wire constants
        VARINT = 0
        FIXED64 = 1
        LENGTH_DELIMITED = 2
        FIXED32 = 5

        def self.encode_export_trace_service_request(span_data)
          # span_data is an Enumerable of SpanData objects
          # This method groups them by resource and scope, then encodes them

          # Message ExportTraceServiceRequest (id=1 repeated ResourceSpans)
          buf = String.new.force_encoding("BINARY")

          # Group span_data by resource
          resource_groups = span_data.group_by(&:resource)

          resource_groups.each do |resource, spans_for_resource|
            rs_buf = encode_resource_spans(resource, spans_for_resource)
            encode_len_field(buf, 1, rs_buf)
          end

          buf
        end

        def self.encode_resource_spans(resource, spans)
          # Message ResourceSpans
          # 1: Resource resource
          # 2: repeated ScopeSpans scope_spans
          # 3: string schema_url (skip for now?)

          buf = String.new.force_encoding("BINARY")

          # Field 1: Resource
          r_buf = encode_resource(resource)
          encode_len_field(buf, 1, r_buf) if r_buf

          # Field 2: ScopeSpans (repeated)
          scope_groups = spans.group_by(&:instrumentation_scope)
          scope_groups.each do |scope, scope_spans|
            ss_buf = encode_scope_spans(scope, scope_spans)
            encode_len_field(buf, 2, ss_buf)
          end

          buf
        end

        def self.encode_resource(resource)
          # Message Resource
          # 1: repeated KeyValue attributes
          # 2: uint32 dropped_attributes_count

          return nil if resource.nil?

          buf = String.new.force_encoding("BINARY")

          resource.attribute_enumerator.each do |key, value|
            kv_buf = encode_key_value(key, value)
            encode_len_field(buf, 1, kv_buf)
          end

          buf
        end

        def self.encode_scope_spans(scope, spans)
          # Message ScopeSpans
          # 1: InstrumentationScope scope
          # 2: repeated Span spans

          buf = String.new.force_encoding("BINARY")

          if scope
            s_buf = encode_instrumentation_scope(scope)
            encode_len_field(buf, 1, s_buf)
          end

          spans.each do |span|
            span_buf = encode_span(span)
            encode_len_field(buf, 2, span_buf)
          end

          buf
        end

        def self.encode_instrumentation_scope(scope)
          # Message InstrumentationScope
          # 1: string name
          # 2: string version

          buf = String.new.force_encoding("BINARY")
          encode_len_field(buf, 1, scope.name) if scope.name
          encode_len_field(buf, 2, scope.version) if scope.version
          buf
        end

        def self.encode_span(span)
          # Message Span
          # 1: bytes trace_id
          # 2: bytes span_id
          # 3: string trace_state
          # 4: bytes parent_span_id
          # 5: string name
          # 6: SpanKind kind
          # 7: fixed64 start_time_unix_nano
          # 8: fixed64 end_time_unix_nano
          # 9: repeated KeyValue attributes
          # 10: uint32 dropped_attributes_count
          # 11: repeated Event events
          # 12: uint32 dropped_events_count
          # 13: repeated Link links
          # 14: uint32 dropped_links_count
          # 15: Status status

          buf = String.new.force_encoding("BINARY")

          encode_len_field(buf, 1, span.trace_id)
          encode_len_field(buf, 2, span.span_id)
          encode_len_field(buf, 3, span.tracestate.to_s) unless span.tracestate.to_s.empty?
          encode_len_field(buf, 4, span.parent_span_id) if span.parent_span_id != "\x00" * 8
          encode_len_field(buf, 5, span.name)

          # Kind (enum)
          kind_val = case span.kind
          when :internal then 1
          when :server then 2
          when :client then 3
          when :producer then 4
          when :consumer then 5
          else 0
          end
          encode_varint_field(buf, 6, kind_val) if kind_val > 0

          encode_fixed64_field(buf, 7, span.start_timestamp)
          encode_fixed64_field(buf, 8, span.end_timestamp)

          if span.attributes
            span.attributes.each do |k, v|
              kv_buf = encode_key_value(k, v)
              encode_len_field(buf, 9, kv_buf)
            end
          end

          # Field 10: dropped_attributes_count
          dropped_attrs = span.total_recorded_attributes - (span.attributes&.length || 0)
          encode_varint_field(buf, 10, dropped_attrs) if dropped_attrs > 0

          if span.events
            span.events.each do |event|
              ev_buf = encode_event(event)
              encode_len_field(buf, 11, ev_buf)
            end
          end

          # Field 12: dropped_events_count
          dropped_events = span.total_recorded_events - (span.events&.length || 0)
          encode_varint_field(buf, 12, dropped_events) if dropped_events > 0

          if span.links
            span.links.each do |link|
              lnk_buf = encode_link(link)
              encode_len_field(buf, 13, lnk_buf)
            end
          end

          # Field 14: dropped_links_count
          dropped_links = span.total_recorded_links - (span.links&.length || 0)
          encode_varint_field(buf, 14, dropped_links) if dropped_links > 0

          if span.status
            st_buf = encode_status(span.status)
            encode_len_field(buf, 15, st_buf)
          end

          buf
        end

        def self.encode_event(event)
          # Message Event
          # 1: fixed64 time_unix_nano
          # 2: string name
          # 3: repeated KeyValue attributes

          buf = String.new.force_encoding("BINARY")
          encode_fixed64_field(buf, 1, event.timestamp)
          encode_len_field(buf, 2, event.name)
          if event.attributes
            event.attributes.each do |k, v|
              kv_buf = encode_key_value(k, v)
              encode_len_field(buf, 3, kv_buf)
            end
          end
          buf
        end

        def self.encode_link(link)
          # Message Link
          # 1: bytes trace_id
          # 2: bytes span_id
          # 3: string trace_state
          # 4: repeated KeyValue attributes

          buf = String.new.force_encoding("BINARY")
          encode_len_field(buf, 1, link.span_context.trace_id)
          encode_len_field(buf, 2, link.span_context.span_id)
          tracestate_str = link.span_context.tracestate.to_s
          encode_len_field(buf, 3, tracestate_str) unless tracestate_str.empty?
          if link.attributes
            link.attributes.each do |k, v|
              kv_buf = encode_key_value(k, v)
              encode_len_field(buf, 4, kv_buf)
            end
          end
          buf
        end

        def self.encode_status(status)
          # Message Status
          # 2: string message (deprecated, but still used)
          # 3: StatusCode code

          buf = String.new.force_encoding("BINARY")
          encode_len_field(buf, 2, status.description) unless status.description.empty?

          code_val = case status.code
          when OpenTelemetry::Trace::Status::OK, :ok then 1 # STATUS_CODE_OK
          when OpenTelemetry::Trace::Status::UNSET, :unset then 0 # STATUS_CODE_UNSET
          when OpenTelemetry::Trace::Status::ERROR, :error then 2 # STATUS_CODE_ERROR
          else 0
          end
          encode_varint_field(buf, 3, code_val) if code_val > 0

          buf
        end

        def self.encode_key_value(key, value)
          # Message KeyValue
          # 1: string key
          # 2: AnyValue value

          buf = String.new.force_encoding("BINARY")
          encode_len_field(buf, 1, key)

          av_buf = encode_any_value(value)
          encode_len_field(buf, 2, av_buf)

          buf
        end

        def self.encode_any_value(value)
          # Message AnyValue (oneof)
          # 1: string
          # 2: bool
          # 3: int64
          # 4: double
          # 5: ArrayValue
          # 6: KeyValueList
          # 7: bytes

          buf = String.new.force_encoding("BINARY")
          case value
          when String
            # UTF-8 string by default
            encode_len_field(buf, 1, value.encode("UTF-8"))
          when true
            encode_varint_field(buf, 2, 1)
          when false
            encode_varint_field(buf, 2, 0)
          when Integer
            encode_varint_field(buf, 3, value)
          when Float
            encode_fixed64_field(buf, 4, value)
          when Array
            # ArrayValue
            av_buf = String.new.force_encoding("BINARY")
            value.each do |item|
              item_buf = encode_any_value(item)
              encode_len_field(av_buf, 1, item_buf)
            end
            encode_len_field(buf, 5, av_buf)
          end
          buf
        end

        # --- Primitives ---

        # Specialized encoder for length-delimited fields (strings, bytes, nested messages)
        # This is the most common field type, so we optimize it heavily
        def self.encode_len_field(buf, field_number, value)
          return if value.nil?

          # Tag for length-delimited is (field_number << 3) | 2
          tag = (field_number << 3) | 2
          buf << tag if tag < 128  # All field numbers 1-15 fit in one byte

          len = value.bytesize
          if len < 128
            buf << len
          elsif len < 16384
            buf << ((len & 0x7F) | 0x80) << (len >> 7)
          else
            encode_varint(buf, len)
          end
          buf << value
        end

        # Specialized encoder for varint fields (enums, integers, booleans)
        def self.encode_varint_field(buf, field_number, value)
          return if value.nil?

          # Tag for varint is (field_number << 3) | 0
          tag = field_number << 3
          buf << tag if tag < 128

          if value >= 0 && value < 128
            buf << value
          elsif value >= 0 && value < 16384
            buf << ((value & 0x7F) | 0x80) << (value >> 7)
          else
            encode_varint(buf, value)
          end
        end

        # Specialized encoder for fixed64 fields (timestamps, doubles)
        def self.encode_fixed64_field(buf, field_number, value)
          return if value.nil?

          # Tag for fixed64 is (field_number << 3) | 1
          tag = (field_number << 3) | 1
          buf << tag if tag < 128

          if value.is_a?(Float)
            buf << [value].pack("E")
          else
            buf << [value].pack("Q<")
          end
        end

        # Generic encode_field kept for backwards compatibility and edge cases
        def self.encode_field(buf, field_number, type, value)
          return if value.nil?

          tag = (field_number << 3) | type
          # Inline varint encoding for tag (always small, usually 1 byte)
          if tag < 128
            buf << tag
          else
            buf << ((tag & 0x7F) | 0x80) << (tag >> 7)
          end

          case type
          when VARINT
            # Inline varint for small values (common case)
            if value >= 0 && value < 128
              buf << value
            elsif value >= 0 && value < 16384
              buf << ((value & 0x7F) | 0x80) << (value >> 7)
            else
              encode_varint(buf, value)
            end
          when LENGTH_DELIMITED
            len = value.bytesize
            # Inline varint for length (usually small)
            if len < 128
              buf << len
            elsif len < 16384
              buf << ((len & 0x7F) | 0x80) << (len >> 7)
            else
              encode_varint(buf, len)
            end
            buf << value
          when FIXED64
            # Little endian 64-bit
            if value.is_a?(Float)
              buf << [value].pack("E")
            else
              buf << [value].pack("Q<")
            end
          when FIXED32
            buf << [value].pack("L<")
          end
        end

        def self.encode_varint(buf, val)
          # Basic varint, handles unsigned.
          # If negative, must be sign extended to 64-bit.
          if val < 0
            val += (1 << 64)
          end

          loop do
            byte = val & 0x7F
            val >>= 7
            if val == 0
              buf << byte
              break
            else
              buf << (byte | 0x80)
            end
          end
        end
      end
    end
  end
end
