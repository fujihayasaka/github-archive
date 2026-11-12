require "rails_helper"
require_relative "../../../lib/one_off_importers/npm"

vcr_options = { cassette_name: "npm-one-off", allow_playback_repeats: true }
describe OneOffImporters::Npm, vcr: vcr_options do
  let(:sink) { Ingest::PackageProcessor.new }

  before do
    @importer = described_class.new(package_name: "react", package_release_sink: sink)
    @request = @importer.request
  end

  it "fetches from npm" do
    expect(@request).to be_a(Hash)
    expect(@request["name"]).to eq("react")
  end

  it "creates outputs an array of package releases" do
    expect(@importer.parse(@request)).to be_a(Array)

    expect(@importer.parse(@request)[0]["package_manager"]).to eq("npm")
    expect(@importer.parse(@request)[0]["package_name"]).to eq("react")
    expect(@importer.parse(@request)[0]["license"]).to eq("MIT")
  end

  it "expects and handles non-URLencoded package_name" do
    imp = described_class.new(package_name: "@kubescape/lens-extension", package_release_sink: sink)
    req = imp.request

    expect(imp.parse(req)).to be_a(Array)
    expect(imp.parse(req)[0]["package_name"]).to eq("@kubescape/lens-extension")
  end

  it "publishes to the sink" do
    expect(sink).to receive(:publish).exactly(212).times
    expect(sink).to receive(:flush)
    expect { @importer.run }.to_not raise_error
  end
end
