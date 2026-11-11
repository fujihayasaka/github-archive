# typed: true
# frozen_string_literal: true

module Twirp
  module Encoding
    # In Twirp 1.7.2 the default behaviour of emitting defaults only in strict mode
    # was changed so that defaults are emitted in all modes. This patch restores
    # the previous behaviour so that we can track our clients as they become
    # compatible with strict mode by adding the "strict=true" to their headers.
    #
    # See https://github.com/twitchtv/twirp-ruby/commit/9f82040807832b34093f02db449a3d5fa5ef92d4
    def self.encode(msg_obj, msg_class, content_type)
      case content_type
      when JSON then msg_class.encode_json(msg_obj, emit_defaults: false)
      when JSON_STRICT then msg_class.encode_json(msg_obj, emit_defaults: true)
      when PROTO then msg_class.encode(msg_obj)
      else raise ArgumentError.new("Invalid content_type")
      end
    end
  end

  if Twirp::VERSION != "1.10.0"
    raise "Twirp version changed to #{Twirp::VERSION}. Please revisit whether the Rack 3 compatibility patches below are still needed."
  end

  # Rack 3 compatibility patches for twirp 1.10.0.
  #
  # twirp 1.10 uses mixed-case 'Content-Type' headers and unconditional body.rewind,
  # both of which break under Rack 3:
  #   - Response headers must be lowercase (Rack 3 UPGRADE-GUIDE.md)
  #   - rack.input is no longer required to be rewindable
  #
  # Backports fixes from twirp 1.13 (https://github.com/arthurnn/twirp-ruby/pull/124)
  # so we can upgrade Rack without upgrading twirp (which requires google-protobuf >= 3.25).
  #
  # Safe on Rack 2: Rack::CONTENT_TYPE is 'Content-Type', Rack::Headers undefined.
  # Remove when twirp is upgraded to 1.13+.
  class Service
    # Override: use Rack::CONTENT_TYPE instead of hardcoded 'Content-Type'
    def self.error_response(twerr)
      status = Twirp::ERROR_CODES_TO_HTTP_STATUS[twerr.code]
      headers = { Rack::CONTENT_TYPE => Encoding::JSON }
      resp_body = Encoding.encode_json(twerr.to_h)
      [status, headers, [resp_body]]
    end

    # Override: use Rack::Headers when available (used in tests only, but patched for completeness)
    def call_rpc(rpc_method, input = {}, env = {})
      base_env = self.class.rpcs[rpc_method.to_s]
      return Twirp::Error.bad_route("Invalid rpc method #{rpc_method.to_s.inspect}") unless base_env

      env = env.merge(base_env)
      input = env[:input_class].new(input) if input.is_a? Hash
      env[:input] = input
      env[:content_type] ||= Encoding::PROTO
      env[:http_response_headers] = Rack.const_defined?(:Headers) ? T.unsafe(Rack).const_get(:Headers).new : {}
      call_handler(env)
    end

    private

    # Override: guard body.rewind + use Rack::Headers when available
    def route_request(rack_env, env)
      rack_request = Rack::Request.new(rack_env)

      if rack_request.request_method != "POST"
        return route_err(:bad_route, "HTTP request method must be POST", rack_request)
      end

      content_type = rack_request.get_header("CONTENT_TYPE")
      if !Encoding.valid_content_type?(content_type)
        return route_err(:bad_route, "Unexpected Content-Type: #{content_type.inspect}. Content-Type header must be one of #{Encoding.valid_content_types.inspect}", rack_request)
      end
      env[:content_type] = content_type

      path_parts = rack_request.path.split("/")
      if path_parts.size < 3 || path_parts[-2] != self.full_name
        return route_err(:bad_route, "Invalid route. Expected format: POST {BaseURL}/#{self.full_name}/{Method}", rack_request)
      end
      method_name = path_parts[-1]

      base_env = self.class.rpcs[method_name]
      if !base_env
        return route_err(:bad_route, "Invalid rpc method #{method_name.inspect}", rack_request)
      end
      env.merge!(base_env)

      input = nil
      begin
        body_str = rack_request.body.read
        rack_request.body.rewind if rack_request.body.respond_to?(:rewind) # Rack 3: input may not be rewindable
        input = Encoding.decode(body_str, env[:input_class], content_type)
      rescue => e
        error_msg = "Invalid request body for rpc method #{method_name.inspect} with Content-Type=#{content_type}"
        if e.is_a?(Google::Protobuf::ParseError)
          error_msg += ": #{e.message.strip}"
        end
        return route_err(:malformed, error_msg, rack_request)
      end

      env[:input] = input
      env[:http_response_headers] = Rack.const_defined?(:Headers) ? T.unsafe(Rack).const_get(:Headers).new : {} # Rack 3: enforce lowercase headers
      nil # -- explicit nil signals success to #call
    end

    # Override: use Rack::CONTENT_TYPE instead of hardcoded 'Content-Type'
    def success_response(output, env)
      env[:output] = output
      @on_success.each { |hook| hook.call(env) }

      headers = env[:http_response_headers].merge(Rack::CONTENT_TYPE => env[:content_type])
      resp_body = Encoding.encode(output, env[:output_class], env[:content_type])
      [200, headers, [resp_body]]
    rescue => e
      exception_response(e, env)
    end
  end
end
