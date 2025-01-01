require "rails_helper"
require "dependency_graph/object_model/abstract_manifest"

RSpec.describe DependencyGraph::ObjectModel::AbstractManifest do
  describe ".normalize_manifest_path" do
    context "with various path formats" do
      TEST_CASES = [
        { input: "./package.json", expected: "package.json", description: "removes leading ./" },
        { input: "/package.json", expected: "package.json", description: "removes leading /" },
        { input: "path/to/package.json", expected: "path/to/package.json", description: "keeps relative paths intact" },
        { input: "/path/to/package.json", expected: "path/to/package.json", description: "removes leading slashes from nested paths" }
      ]

      TEST_CASES.each do |test_case|
        it test_case[:description] do
          result = described_class.normalize_manifest_path(test_case[:input])
          expect(result).to eq(test_case[:expected])
        end
      end
    end
  end
end
