require "rails_helper"
require_relative "../../../lib/one_off_importers/composer.rb"

vcr_options = { cassette_name: "composer-one-off", allow_playback_repeats: true }
describe OneOffImporters::Composer, vcr: vcr_options do
  let(:sink) { Ingest::PackageProcessor.new }

  before do
    @importer = described_class.new(package_name: "symfony/polyfill-mbstring", package_release_sink: sink)
    @request = @importer.request
  end

  it "fetches from packagist" do
    expect(@request).to be_a(Hash)
    expect(@request["v1.0.0"]["name"]).to eq("symfony/polyfill-mbstring")
  end

  it "outputs an array of package releases" do
    expect(@importer.parse(@request)).to be_a(Array)

    expect(@importer.parse(@request)[0]["package_manager"]).to eq("composer")

    expect(@importer.parse(@request)[0]["package_name"]).to eq("symfony/polyfill-mbstring")

    expect(@importer.parse(@request)[0]["dependencies"].size).to eq(1)

    expect(@importer.parse(@request)[0]["dependencies"][0][:package_name]).to eq("php")
  end

  it "publishes to the sink" do
    expect(sink).to receive(:publish).exactly(17).times
    expect(sink).to receive(:flush)
    expect { @importer.run }.to_not raise_error
  end

  it "errors gracefully" do
    bad_import = described_class.new(package_name: "non-exisistent-composer-omg-not-bach", package_release_sink: sink)
    expect { bad_import.request }.to raise_error /Error requesting Composer package/
  end
end
