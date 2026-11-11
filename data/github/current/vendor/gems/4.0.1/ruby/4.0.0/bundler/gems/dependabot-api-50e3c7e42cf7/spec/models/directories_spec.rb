# frozen_string_literal: true

require "rails_helper"

RSpec.describe Directories do
  it "is immutable" do
    directories = described_class.new(%w(/this /that /the /other))

    expect(directories).to be_frozen
  end

  describe "homogenization" do
    context "with a single input" do
      [nil, "", "/", "/.", ".", "//"].each do |dir|
        it "cleans the root directory: #{dir}" do
          result = described_class.new(dir).to_a
          expected = ["/."]

          expect(result).to eq(expected)
          expect(described_class.new(result).to_a).to eq(expected)
        end
      end

      ["path", "/path", "/path/"].each do |dir|
        it "cleans directory with path: #{dir}" do
          result = described_class.new(dir).to_a
          expected = ["/path"]

          expect(result).to eq(expected)
          expect(described_class.new(result).to_a).to eq(expected)
        end
      end
    end

    context "with multiple inputs" do
      it "cleans the root directories" do
        directories = [nil, "", "/foo/path", "/bar/path", "/", "//foo/src/path/"]
        result = described_class.new(directories).to_a
        expected = ["/.", "/bar/path", "/foo/path", "/foo/src/path"]

        expect(result).to eq(expected)
        expect(described_class.new(result).to_a).to eq(expected)
      end

      it "cleans the paths" do
        directories = ["path", "/foo/path", "/bar/path/", "/bar/path", "bar"]
        result = described_class.new(directories).to_a
        expected = ["/bar", "/bar/path", "/foo/path", "/path"]

        expect(result).to eq(expected)
        expect(described_class.new(result).to_a).to eq(expected)
      end
    end
  end

  describe "#each" do
    it "allows the object to be enumerable" do
      directories = %w(/one /two /three /four /five)

      expect(described_class.new(directories).each).to be_a Enumerator
      expect(described_class.new(directories).to_a).to match_array(directories)
      expect(described_class.new(directories).count).to eq(directories.count)
      expect(described_class.new(directories).map(&:itself)).to match_array(directories)
    end
  end

  describe "#==" do
    it "returns true if the entries are the same" do
      entries = %w(/abcd /efg /hijk /lmnop /qrs /tuv /wxyz)
      directories = described_class.new(entries)
      same_directories = described_class.new(entries)

      expect(directories).to eq(same_directories)
    end

    it "returns false if the entries vary" do
      directories = described_class.new(%w(/1 /2 /3))
      slightly_different_directories = described_class.new(%w(/1 /2 /4))

      expect(directories).not_to eq(slightly_different_directories)
    end
  end

  describe "#eql?" do
    it "returns true if the entries are the same" do
      entries = %w(/abcd /efg /hijk /lmnop /qrs /tuv /wxyz)
      directories = described_class.new(entries)
      same_directories = described_class.new(entries)

      expect(directories).to be_eql(same_directories)
    end

    it "returns false if the entries vary" do
      directories = described_class.new(%w(/1 /2 /3))
      slightly_different_directories = described_class.new(%w(/1 /2 /4))

      expect(directories).not_to be_eql(slightly_different_directories)
    end
  end

  describe "#hash" do
    it "is the same if the entries are the same" do
      entries = %w(/abcd /efg /hijk /lmnop /qrs /tuv /wxyz)
      directories = described_class.new(entries)
      same_directories = described_class.new(entries)

      expect(directories.hash).to eq(same_directories.hash)
    end

    it "is not the same if the entries differ" do
      directories = described_class.new(%w(/1 /2 /3))
      slightly_different_directories = described_class.new(%w(/1 /2 /4))

      expect(directories.hash).not_to eq(slightly_different_directories.hash)
    end
  end

  describe "#cover?" do
    it "raises ArgumentError if a glob is provided" do
      directories = described_class.new("/abc", "/def")

      expect { directories.cover?("/abc/*") }.to raise_error(ArgumentError)
    end

    it "accepts one or more directory patterns" do
      directories = described_class.new("/abc", "/def")

      single_pattern = "/abc"
      double_pattern = %w(/abc /def)

      expect(directories.overlap?(single_pattern)).to be true
      expect(directories.overlap?(double_pattern)).to be true
    end

    it "returns true when a pattern matches" do
      dir = "/home"
      directories = described_class.new(dir)

      expect(directories.overlap?(dir)).to be true
    end

    it "returns false when no patterns are provided" do
      dir = "/home"
      directories = described_class.new(dir)

      expect(directories.overlap?("")).to be false
    end

    it "returns false when no patterns match" do
      dir = "/home"
      directories = described_class.new(dir)
      non_matching_pattern = "/away"

      expect(directories.overlap?(non_matching_pattern)).to be false
    end
  end

  describe "#overlap?" do
    it "accepts one or more directory patterns" do
      directories = described_class.new("/abc", "/def")

      single_pattern = "/abc"
      double_pattern = %w(/abc /def)

      expect(directories.overlap?(single_pattern)).to be true
      expect(directories.overlap?(double_pattern)).to be true
    end

    it "returns true when a pattern matches" do
      dir = "/home"
      directories = described_class.new(dir)

      expect(directories.overlap?(dir)).to be true
    end

    it "returns false when no patterns are provided" do
      dir = "/home"
      directories = described_class.new(dir)

      expect(directories.overlap?("")).to be false
    end

    it "returns false when no patterns match" do
      dir = "/home"
      directories = described_class.new(dir)
      non_matching_pattern = "/away"

      expect(directories.overlap?(non_matching_pattern)).to be false
    end

    it "handles single-directory globs" do
      dir = "/home"
      directories = described_class.new(dir)
      current_directory_glob = "*"

      expect(directories.overlap?(current_directory_glob)).to be true
    end

    it "handles recursive globs" do
      nested_dir = "/so/far/from/home"
      directories = described_class.new(nested_dir)
      recursive_glob = "**/*"

      expect(directories.overlap?(recursive_glob)).to be true
    end

    %w(h?m? h[aeiou]m[aeiou] [!aeiou]o[!aeiou]e h*m*).each do |wildcard_pattern|
      it "handles the wildcard pattern: #{wildcard_pattern}" do
        dir = "/home"
        directories = described_class.new(dir)

        expect(directories.overlap?(wildcard_pattern)).to be true
      end
    end

    context "when both directories have globs and can't be determined if they overlap" do
      test_cases = [
        { left: "/a/*", right: "/a/*" },
        { left: "/hello/**/*", right: "/hello/*/*" },
        { left: ["/a", "/**"], right: ["/*"] },
        { left: ["/[abc]"], right: ["/[xyz]"] },
        { left: ["/*/bar"], right: ["/*/foo"] },
        { left: "/*", right: "/foo-*" },
        { left: "/foo/*", right: "/foo/*/bar" },
        { left: "/foo/**/*", right: "/foo/*" },
        { left: "/foo/{a,b}", right: "/foo/{c,d}" },
      ].map { |v| OpenStruct.new(v) }

      test_cases.each do |test|
        it "raises an error for the directories: #{test.left} and #{test.right}" do
          expect do
            described_class.new(test.left).overlap?(test.right)
          end.to raise_error(Directories::IndeterminateOverlapError)
        end
      end
    end

    it "returns false if two globs have different prefixes" do
      expect(described_class.new("/hello/world/*", "/hello/*").overlap?(["/house/{a,b}", "/away/*"])).to be false
      expect(described_class.new("/a", "/b/?").overlap?("/c-*")).to be false
      expect(described_class.new("/foo/bar/*", "/foo/*").overlap?(["/baz/{a,b}", "/qux/*"])).to be false
      expect(described_class.new("/x/y/z/*", "/x/*").overlap?(["/a/{b,c}", "/d/*"])).to be false
      expect(described_class.new("/abc/def/*", "/abc/*").overlap?(["/ghi/{j,k}", "/lmn/*"])).to be false
    end
  end

  describe "#contains_glob?" do
    %w(* ? [ ] { }).each do |glob_character|
      it "returns true if a directory contains a glob character: #{glob_character}" do
        directories = described_class.new("/home", "/away", "/home/#{glob_character}")

        expect(directories.contains_glob?).to be true
      end
    end

    it "returns true if a directory contains brace expansion patterns" do
      directories = described_class.new("/home", "/away", "/home/{a,b,c}")
      expect(directories.contains_glob?).to be true

      directories = described_class.new("/home/{prod,dev}")
      expect(directories.contains_glob?).to be true
    end

    it "returns false if no directories contain a glob character" do
      directories = described_class.new("/home", "/away", "/^home/&star/~runner")

      expect(directories.contains_glob?).to be false
    end

    it "returns false if glob patterns are escaped with '\\'" do
      directories = described_class.new("/home", "/away", "/home/\\*")

      expect(directories.contains_glob?).to be false
    end

    it "returns false if directory names contain glob characters but they are escaped" do
      directories = described_class.new("/home", "/away", "\\{\\{ template \\}\\}", "\\[\\[ template \\]\\]")

      expect(directories.contains_glob?).to be false
    end

    # Escape sequences
    it "returns true for unescaped glob characters" do
      directories = described_class.new("/home/*")
      expect(directories.contains_glob?).to be true
    end

    # Homogenization - unescaping
    it "unescapes glob characters and stores literal directory names" do
      directories = described_class.new("\\{\\{cookiecutter.name\\}\\}")
      expect(directories.to_a).to eq(["/{{cookiecutter.name}}"])
    end

    it "handles double backslash correctly" do
      directories = described_class.new("/path/\\*")
      expect(directories.to_a).to eq(["/path/*"])
    end

    # Cover method
    it "raises ArgumentError for wildcard patterns" do
      directories = described_class.new("/abc")
      expect { directories.cover?("/abc/*") }.to raise_error(ArgumentError)
      # Other characters like ?, {}, [] are allowed in literal directory names
      expect { directories.cover?("/abc/?") }.not_to raise_error
      expect { directories.cover?("/abc/{a,b}") }.not_to raise_error
    end
  end
end
