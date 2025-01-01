require "rails_helper"
require_relative "../../../lib/one_off_importers/rubygems"

vcr_options = { cassette_name: "rubygems-one-off", allow_playback_repeats: true }
describe OneOffImporters::Rubygems, vcr: vcr_options do
  let(:sink) { Ingest::PackageProcessor.new }

  before do
    @importer = described_class.new(package_name: "rails", package_release_sink: sink)
    @request = @importer.request
  end

  it "fetches from rubygems" do
    expect(@request).to be_a(Hash)
    expect(@request["info"]["name"]).to eq("rails")
  end

  it "outputs an array of package releases" do
    expect(@importer.parse(@request)).to be_a(Array)

    expect(@importer.parse(@request)[0]["package_manager"]).to eq("rubygems")

    expect(@importer.parse(@request)[0]["package_name"]).to eq("rails")

    expect(@importer.parse(@request)[0]["home_url"]).to include("rubyonrails.org")

    expect(@importer.parse(@request)[0]["dependencies"].size).to eq(12)

    expect(@importer.parse(@request)[0]["dependencies"][0][:package_name]).to eq("actioncable")

    expect(@importer.parse(@request)[0]["dependencies"][0][:scope]).to eq(:runtime)
  end

  it "publishes to the sink" do
    expect(sink).to receive(:publish).exactly(352).times
    expect(sink).to receive(:flush)
    expect { @importer.run }.to_not raise_error
  end

  it "errors gracefully" do
    bad_import = described_class.new(package_name: "non-exisistent-gem-omg", package_release_sink: sink)
    expect { bad_import.request }.to raise_error /Error requesting Rubygems package/
  end
end
