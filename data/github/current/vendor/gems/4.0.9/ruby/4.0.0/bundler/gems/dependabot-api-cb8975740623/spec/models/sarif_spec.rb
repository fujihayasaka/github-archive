# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sarif, type: :model do
  describe "initialization" do
    it "can be initialized with a Hash or String (JSON)" do
      sarif_as_hash = from_fixture("styled-components.sarif").to_json
      sarif_as_json = from_fixture("styled-components.sarif")

      from_hash = described_class.new(sarif_as_hash)
      from_json = described_class.new(sarif_as_json)

      expect(from_hash.dependency_declaration_location).
        to eq(from_json.dependency_declaration_location)
    end
  end

  describe "#dependency_declaration_location" do
    it "returns a Hash" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.dependency_declaration_location).to be_a(Hash)
    end

    it "includes a :file_path" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.dependency_declaration_location).
        to include({ file_path: "package.json" })
    end

    it "includes a :start_column" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.dependency_declaration_location).
        to include({ start_column: 1 })
    end

    it "includes an :end_column" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.dependency_declaration_location).
        to include({ end_column: 32 })
    end

    it "includes a :start_line" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.dependency_declaration_location).
        to include({ start_line: 82 })
    end

    it "includes a :end_line" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.dependency_declaration_location).
        to include({ end_line: 82 })
    end
  end

  describe "#affected_file_paths" do
    it "returns a collection" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.affected_file_paths).to be_a(Enumerable)
    end

    it "returns the file paths of files to-be-updated" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.affected_file_paths).
        to match_array([
                         "components/article/ArticleGridLayout.tsx",
                         "pages/_document.tsx",
                       ])
    end
  end

  describe "#message" do
    it "returns the error message from the SARIF" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.message).to eq(<<~MESSAGE.squish)
        This JSX tag's 'children' prop expects type 'never' which requires
        multiple children, but only a single child was provided.---Type 'string'
        is not assignable to type 'never'.
      MESSAGE
    end
  end

  describe "#level" do
    it "returns the error level from the SARIF" do
      sarif = from_fixture("styled-components.sarif")

      instance = described_class.new(sarif)

      expect(instance.level).to eq("failure")
    end
  end

  def from_fixture(fixture_name)
    JSON.parse(fixture("sarif/#{fixture_name}"))
  end
end
