require "rails_helper"
require_relative "../../../lib/one_off_importers/nuget.rb"

vcr_options = { cassette_name: "nuget-one-off", allow_playback_repeats: true }
describe OneOffImporters::Nuget, vcr: vcr_options do
  let(:sink) { Ingest::PackageProcessor.new }

  before do
    @importer = described_class.new(package_name: "Microsoft.VisualStudio.Editor", package_release_sink: sink)
    @request = @importer.request
  end

  it "fetches from nuget" do
    expect(@request).to be_a(Hash)
    expect(@request["items"][0]["items"][0]["catalogEntry"]["id"]).to eq("Microsoft.VisualStudio.Editor")
  end

  it "outputs an array of package releases" do
    expect(@importer.parse(@request)).to be_a(Array)

    expect(@importer.parse(@request)[0]["package_manager"]).to eq("nuget")

    expect(@importer.parse(@request)[0]["package_name"]).to eq("Microsoft.VisualStudio.Editor")

    expect(@importer.parse(@request)[0]["dependencies"].size).to eq(8)

    expect(@importer.parse(@request)[0]["dependencies"][0][:package_name]).to eq("Microsoft.VisualStudio.TextManager.Interop.8.0")
  end

  it "publishes to the sink" do
    expect(sink).to receive(:publish).exactly(31).times
    expect(sink).to receive(:flush)
    expect { @importer.run }.to_not raise_error
  end

  it "handles nuget packages that paginate versions" do
    paginated_importer = described_class.new(package_name: "xamarin.forms", package_release_sink: sink)
    paginated_request = paginated_importer.request
    expect(paginated_request).to be_a(Hash)

    parsed = paginated_importer.parse(paginated_request)
    expect(parsed.size).to eq(238)
    expect(parsed[0]["package_manager"]).to eq("nuget")
    expect(parsed[0]["package_name"]).to eq("Xamarin.Forms")

    expect { paginated_importer.run }.to_not raise_error
  end

  it "errors gracefully" do
    bad_import = described_class.new(package_name: "non-exisistent-nugget-omg", package_release_sink: sink)
    expect { bad_import.request }.to raise_error /Error requesting Nuget package/
  end
end
