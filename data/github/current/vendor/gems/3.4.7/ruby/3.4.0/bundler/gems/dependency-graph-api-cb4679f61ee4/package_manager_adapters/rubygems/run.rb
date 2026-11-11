require "active_record"
require "logging"
require "data_dump"
require "data_restore"
require "models"
require "extractor"
require "httparty"

# Get DB override configs if running in dotcom production Moda env
POSTGRES_USER = ENV.fetch("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = ENV.fetch("POSTGRES_PASSWORD", "ruby-pma-pg")
POSTGRES_MODA_SIDECAR_ENABLED = ENV.fetch("POSTGRES_MODA_SIDECAR_ENABLED", nil)

begin
  # Get Sink Proxy URL from Production Environment
  SINK_PROXY_URL = ENV.fetch("SINK_PROXY_URL")
rescue KeyError => e
  # If not in production, explicitly set sink proxy url
  # URL is dependent on OS; Mac or Linux
  if RUBY_PLATFORM =~ /darwin/
    SINK_PROXY_URL = "http://host.docker.internal:7777"
  else
    SINK_PROXY_URL = "http://localhost:7777"
  end
end

def report_error(e)
  HTTParty.post("#{SINK_PROXY_URL}/errors", {
    body: {
      message: e.message,
      backtrace: e.backtrace.join("\n")
    }
  })
end

begin
  data_dump = DataDump.new(data_dir: "/src/app/package_manager_adapters/rubygems/data_dumps")
  data_dump.download_latest

  opts = {
    adapter: :postgresql,
    pool: 60,
    timeout: 10000, # 10 seconds
    database: "rubygems"
  }

  # apply additional overrides if this is dotcom production Moda env
  opts.merge!({
    host: "localhost", # containers in same pod share IP addr etc.
    user: POSTGRES_USER,
    password: POSTGRES_PASSWORD,
  }) unless POSTGRES_MODA_SIDECAR_ENABLED.nil?

  DataRestore.load(
    dump: data_dump.output,
    user: opts[:user],
    database: opts[:database],
    host: opts[:host],
  )

  Models::Base.establish_connection(opts)

  Extractor.run(sink_proxy_url: SINK_PROXY_URL)
rescue StandardError => e
  report_error(e)
  raise e
end
