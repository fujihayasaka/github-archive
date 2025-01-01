require "rails_helper"
require_relative "../../../lib/one_off_importers/base"

describe OneOffImporters::Base do
  it "raises an exception if one of the methods isn't overridden" do
    importer = described_class.new(package_name: "octokit")

    expect { importer.request }.to raise_exception(NotImplementedError)

    expect { importer.parse(importer.request) }.to raise_exception(NotImplementedError)
  end
end
