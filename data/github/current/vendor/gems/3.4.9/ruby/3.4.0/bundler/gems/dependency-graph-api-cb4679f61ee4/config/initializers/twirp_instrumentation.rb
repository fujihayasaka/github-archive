# Primitive attempt at automatic Twirp instrumentation after a discussion with
# @arielvalentin. Eventual goal is to get some version of this upstream into
# Github::Telemetry or opentelemetry-contrib.
module TwirpClientInstrumentationPatch
  def rpc(rpc_method, input, req_opts = nil)
    GitHub::Telemetry.tracer.in_span("#{@service_full_name}/#{rpc_method}", kind: :client, attributes: {
      "rpc.system" => "twirp",
      "rpc.service" => @service_full_name,
      "rpc.method" => rpc_method.to_s
    }) do
      super(rpc_method, input, req_opts)
    end
  end
end

Twirp::Client.prepend(TwirpClientInstrumentationPatch)
