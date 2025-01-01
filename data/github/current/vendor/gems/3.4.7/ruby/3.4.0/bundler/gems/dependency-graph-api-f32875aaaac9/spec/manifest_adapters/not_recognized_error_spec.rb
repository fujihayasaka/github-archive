require "rails_helper"

describe ManifestAdapters::NotRecognizedError do
  it "wraps unrecognized manifest exceptions" do
    err = described_class.new(filename: "funky-requirements.txt",
                              path: "wanna/get/by")

    expect(err.filename).to eq("funky-requirements.txt")
    expect(err.path).to eq("wanna/get/by")
  end
end
