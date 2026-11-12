require "rails_helper"
require_relative "../../../lib/one_off_importers/pypi"

vcr_options = { cassette_name: "pypi-one-off", allow_playback_repeats: true }
describe OneOffImporters::Pypi, vcr: vcr_options do
  let(:sink) { Ingest::PackageProcessor.new }

  before do
    @importer = described_class.new(package_name: "octokit", package_release_sink: sink)
    @request = @importer.request
  end

  it "fetches from pypi" do
    expect(@request).to be_a(Hash)
    expect(@request["info"]["name"]).to eq("octokit")
  end

  it "creates outputs an array of package releases" do
    expect(@importer.parse(@request)).to be_a(Array)

    expect(@importer.parse(@request)[0]["package_manager"]).to eq("pip")

    expect(@importer.parse(@request)[0]["package_name"]).to eq("octokit")
  end

  it "publishes to the sink" do
    expect(sink).to receive(:publish).exactly(1).times
    expect(sink).to receive(:flush)
    expect { @importer.run }.to_not raise_error
  end
end
