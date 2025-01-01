require "rails_helper"
require_relative "../../etl/sink_proxy"

describe SinkProxy do
  let(:app) { described_class }

  include Rack::Test::Methods

  describe "a POST to /package_releases" do
    let(:sink) { Ingest::PackageProcessor.new }
    let(:messages) { sink.spec_publisher.sink.messages }

    before do
      app.set :package_release_sink, sink
    end

    after do
      sink.spec_reset
    end

    context "valid requests" do
      let(:package_name) { "express" }
      let(:package_manager) { :npm }

      before do
        post "/package_releases", {
          package_releases: [{
            package_manager: package_manager,
            package_name:    package_name,
            namespace:       "github",
            version:         "4.14.1",
            dependencies: [
              {
                package_name: "etag",
                requirements: "~1.7.0",
              },
              {
                package_name: "mocha",
                requirements:  "3.2.0",
                scope:        :development,
              }
            ]
          }].to_json
        }
      end

      it "is successful" do
        expect(last_response.status).to eq 200
      end

      it "publishes a package release" do
        expect(messages.count).to eq 1
      end

      it "instruments" do
        expect {
          post "/package_releases", {
            package_releases: [{
              package_manager: :npm,
              package_name:    "express",
              version: "4.14.1",
            }].to_json
          }
        }.to have_instrumented_count("etl.package_releases.processed", 1, {
          stage: "extraction",
          package_manager: :npm
        })
      end

      describe "the package release" do
        let(:release)            { decoded_message(messages.first) }
        let(:runtime_dependency) { release["dependencies"].first }
        let(:dev_dependency)     { release["dependencies"].last }

        specify { expect(release["package_manager"]).to eq Types::PackageManager[:npm].to_s }
        specify { expect(release["package_name"]).to eq "express" }
        specify { expect(release["namespace"]).to eq "github" }
        specify { expect(release["package_version"]).to eq "4.14.1" }

        specify { expect(runtime_dependency["package_name"]).to eq "etag" }
        specify { expect(runtime_dependency["requirements"]).to eq "~1.7.0" }

        specify { expect(dev_dependency["package_name"]).to eq "mocha" }
        specify { expect(dev_dependency["requirements"]).to eq "3.2.0" }
        specify { expect(dev_dependency["scope"]).to eq Types::Scope[:development].name.to_s }
      end
    end

    context "invalid requests" do
      before { app.set :raise_errors, false }

      it "doesn't accept incomplete data" do
        post "/package_releases", {
          package_releases: [{
            package_name:    "express",
            version:         "4.14.1",
          }].to_json
        }

        expect(last_response.status).to eq 400
        expect(parsed_response["message"]).to eq({ "package_manager" => ["can't be blank"] })
        expect(messages).to be_empty
      end

      it "handles empty requests" do
        post "/package_releases"

        expect(last_response.status).to eq 200
        expect(messages).to be_empty
      end
    end
  end

  describe "a POST to /errors" do
    it "reports to failbot" do
      e = SinkProxy::SinkError.new("oh no")
      e.set_backtrace(%w{ line-1 line-2 })

      expect(Failbot).to receive(:report).with(e)

      post "/errors", {
        message: "oh no",
        backtrace: "line-1\nline-2\n"
      }
      post "/errors", { message: e.message, backtrace: e.backtrace }
    end
  end

  describe "checkpointing" do
    it "stores checkpoints" do
      post "/checkpoints", { id: "npm_sink" }
      expect(parsed_response[:value]).to eq(0)

      get "/checkpoints/npm_sink"
      expect(parsed_response[:value]).to eq(0)

      put "/checkpoints/npm_sink", { value: 10 }
      expect(parsed_response[:value]).to eq(10)
    end

    it "returns an error when values are invalid" do
      put "/checkpoints/npm_sink", { value: "NaN" }
      expect(last_response.status).to eq(422)

      put "/checkpoints/npm_sink", { value: nil }
      expect(last_response.status).to eq(422)
    end
  end

  def parsed_response
    JSON.parse(last_response.body).with_indifferent_access
  end

  def decoded_message(message)
    Hydro::Decoding::ProtobufDecoder.decode(message.data).to_h.with_indifferent_access
  end
end
