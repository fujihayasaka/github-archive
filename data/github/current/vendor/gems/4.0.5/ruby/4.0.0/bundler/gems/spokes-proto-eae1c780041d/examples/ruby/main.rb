require "openssl"
require "spokes-proto"

SERVICE_NAME = "example-service"
CURRENT_SHA = "(replace this with your repository's current commit sha)"

if ENV["SPOKESD_CA_FILE"] && ENV["SPOKESD_CLIENT_CERT"] && ENV["SPOKESD_CLIENT_KEY"]
  ssl =
    begin
      {
        ca_file: ENV["SPOKESD_CA_FILE"],
        client_cert: OpenSSL::X509::Certificate.new(ENV["SPOKESD_CLIENT_CERT"]),
        client_key: OpenSSL::PKey::EC.new(ENV["SPOKESD_CLIENT_KEY"]),
      }
    rescue => e
      puts "warning: TLS is disabled: #{e}"
      nil
    end
else
  puts "warning: TLS config not found, run 'source env.sh' before running this!"
end

spokesd_url = ARGV[0] || "https://127.0.0.1:12443"

class RequestHMAC
  def initialize(app, key: ENV["HMAC_KEY"], algorithm: "sha256")
    @app = app
    @key = key
    @algorithm = algorithm
  end

  def call(env)
    env[:request_headers]["Request-HMAC"] = generate_header(Time.now)
    @app.call(env)
  end

  def generate_header(time)
    timestamp = time.to_i.to_s
    hmac = OpenSSL::HMAC.hexdigest(@algorithm, @key, timestamp)
    "#{timestamp}.#{hmac}"
  end
end

client = GitHub::Spokes::Proto::Client.new("#{spokesd_url}/twirp", service_name: SERVICE_NAME, current_sha: CURRENT_SHA, ssl: ssl) do |conn|
  ## Configure middleware, e.g. for observability or resliency.

  # conn.use GitHub::FaradayMiddleware::Datadog, stats: Rails.application.stats, service_name: SERVICE_NAME

  # conn.use GitHub::FaradayMiddleware::Tracer,
  #          service_name: SERVICE_NAME,
  #          parent_span: proc { OpenTracing.global_tracer&.active_span },
  #          tracer: OpenTracing.global_tracer,
  #          # If we don't specify the operation, it defaults to "POST", in
  #          # which case LightStep produces an operation that filters the last
  #          # component of the URL.  Since in Twirp, that's the RPC method
  #          # name, which we want to keep, we set the operation explicitly
  #          # ourselves.
  #          operation: proc { |env| "#{env[:method].to_s.upcase} #{URI(env[:url]).path}" }

  conn.use RequestHMAC

  conn.request :retry, max: 3, retry_statuses: [503]

  ## If you want to use a different Faraday adapter, do that here, too.
  # conn.adapter :typhoeus
end

# Use new_repository or new_gist or new_wiki to set up the context for your requests.
repository = GitHub::Spokes::Proto::Types.new_repository(1)

cursor = nil
loop do
  # Call TreesAPI.ListTrees
  resp = client.trees.list_trees(
    request_context: {quality_of_service: :QUALITY_OF_SERVICE_DELAYABLE},
    repository: repository,
    treeish_selector: {
      treeish: {reference: {name: "HEAD"}},
    },
    recursive: true,
    cursor: cursor,
  )

  if resp.error
    puts "error: twirp error #{resp.error.code}: #{resp.error.msg}"
    exit 1
  end

  resp.data.entries.each do |entry|
    puts "mode:#{'%06o' % entry.mode.mode} type:#{entry.object.type} oid:#{entry.object.oid.id} path:#{entry.path.name}"
  end

  cursor = resp.data.next_cursor
  break if cursor.nil?
end
