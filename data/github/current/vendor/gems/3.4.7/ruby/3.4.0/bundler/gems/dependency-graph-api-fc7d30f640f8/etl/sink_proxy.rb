require "sinatra/base"
require "failbot"
require "failbot/middleware"
require_relative "../lib/rack/request_logger"

class SinkProxy < Sinatra::Base
  set :show_exceptions, false
  enable :raise_errors
  use Rack::RequestLogger
  use Failbot::Rescuer, app: "dependency-graph-api"

  error do
    content_type :json
    status 400

    { result: "error", message: env["sinatra.error"].message }.to_json
  end

  get "/status" do
    { status: "ok" }.to_json
  end

  post "/package_releases" do
    package_release_params.each_slice(100) do |slice|
      slice.each do |attributes|
        release = build_package_release(attributes)

        if release.valid?
          package_release_sink.publish(OneOffImporters.build_hash(attributes))
        else
          status 400
          return {
            result: "error",
            message: release.errors.to_hash
          }.to_json
        end
      end

      package_release_sink.flush

      Instrument.count("etl.package_releases.processed", slice.count,
                       package_manager: slice.first["package_manager"].to_sym,
                       stage: "extraction")
    end

    nil
  end

  post "/checkpoints" do
    { value: checkpoint.get }.to_json
  end

  put "/checkpoints/:id" do
    unless checkpoint_value_valid?
      status 422
      return "Checkpoint value #{checkpoint_value.inspect} is invalid"
    end

    checkpoint.update(last_checkpointed_id: params[:value])

    { value: checkpoint.get }.to_json
  end

  get "/checkpoints/:id" do
    { value: checkpoint.get }.to_json
  end

  class SinkError < RuntimeError; end

  post "/errors" do
    exception = SinkError.new(params[:message])

    if params[:backtrace]
      exception.set_backtrace(params[:backtrace].split("\n"))
    end

    Failbot.report(exception)
  end

  private

  def build_package_release(attributes)
    Packages::PackageRelease.new(
      package_manager: attributes["package_manager"]&.to_sym,
      package_name: attributes["package_name"],
      namespace: attributes["namespace"],
      version: attributes["version"],
      description: attributes["description"],
      authors: attributes["authors"],
      download_count: attributes["download_count"],
      external_id: attributes["external_id"],
      source_url: attributes["source_url"],
      home_url: attributes["home_url"],
      docs_url: attributes["docs_url"],
      published_at: parse_time(attributes["published_at"]),
      unpublished_at: parse_time(attributes["unpublished_at"]),
      built_at: parse_time(attributes["built_at"]),
      dependencies: Array(attributes["dependencies"]).map { |dependency|
        Packages::PackageRelease::Dependency.new(
          package_name: dependency["package_name"],
          requirements: dependency["requirements"],
          scope: dependency["scope"]&.to_sym || :runtime,
        )
      }
    )
  end

  def checkpoint
    @checkpoint ||= Checkpoint.with_name(params[:id]).first_or_create!(last_checkpointed_id: 0)
  end

  def checkpoint_value_valid?
    return false if params[:value].blank?

    begin
      !!Integer(params[:value])
    rescue ArgumentError
      false
    end
  end

  def checkpoint_value
    params[:value]
  end

  def package_release_params
    return [] unless params[:package_releases].present?

    Array(JSON.parse(params[:package_releases]))
  end

  def package_release_sink
    settings.package_release_sink || default_package_release_sink
  end

  def default_package_release_sink
    Thread.current[:package_release_sink] ||= Ingest::PackageProcessor.new
  end

  def parse_time(time)
    Time.at(time) if time.present?
  end
end
