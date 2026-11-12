# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitHub::Twirp::DependabotPullRequests::DependencyFileProtobufAdapter do
  let(:proto_dependency_class) do
    MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile
  end

  it "requires a Dependabot::DependencyFile as an argument" do
    expect { described_class.new(File.new) }.to raise_error(ArgumentError)

    file = dependency_file
    expect { described_class.new(file) }.not_to raise_error
  end

  %i(content deleted directory name support_file).each do |attr_name|
    it "forwards #{attr_name} to the dependency file" do
      file = dependency_file
      adapter = described_class.new(file)

      expect(adapter.public_send(attr_name)).to eq(file.public_send(attr_name))
    end
  end

  describe "#to_proto" do
    it "returns a protobuf-friendly dependency file" do
      adapter = described_class.new(dependency_file)

      expect(adapter.to_proto).to be_a(proto_dependency_class)
    end

    it "populates the fields accordingly" do
      file = dependency_file(mode: "100644", type: described_class::SYMLINK_TYPE, symlink_target: "/.target")
      adapter = described_class.new(file)
      proto_file = adapter.to_proto

      expect(proto_file.content).to eq(file.content)
      expect(proto_file.directory).to eq(file.directory)
      expect(proto_file.support_file).to eq(file.support_file)
      expect(proto_file.deleted).to eq(file.deleted)
      expect(proto_file.mode).to eq(file.mode)
      expect(proto_file.symlink_target).to eq(file.symlink_target)
    end

    it "uses protobuf-friendly values for file types" do
      adapter = described_class.new(dependency_file(type: described_class::SUBMODULE_TYPE))
      proto_file = adapter.to_proto

      expected_type = proto_dependency_class::Type.lookup(proto_dependency_class::Type::TYPE_SUBMODULE)
      expect(proto_file.type).to eq(expected_type)
    end

    it "uses protobuf-friendly values for content encoding" do
      adapter =
        described_class.new(dependency_file(content_encoding: Dependabot::DependencyFile::ContentEncoding::UTF_8))
      proto_file = adapter.to_proto

      expected_encoding =
        proto_dependency_class::ContentEncoding.lookup(proto_dependency_class::ContentEncoding::CONTENT_ENCODING_UTF8)
      expect(proto_file.content_encoding).to eq(expected_encoding)
    end
  end

  describe "#content_encoding" do
    it "sets encoding to protobuf-friendly values" do
      adapter = described_class.new(dependency_file)

      adapter.content_encoding = Dependabot::DependencyFile::ContentEncoding::UTF_8
      expect(adapter.content_encoding).
        to eq(proto_dependency_class::ContentEncoding::CONTENT_ENCODING_UTF8)

      adapter.content_encoding = Dependabot::DependencyFile::ContentEncoding::BASE64
      expect(adapter.content_encoding).
        to eq(proto_dependency_class::ContentEncoding::CONTENT_ENCODING_BASE64)
    end

    it "declares unexpected values invalid" do
      adapter = described_class.new(dependency_file)

      %w(ascii gzip json text/html unicode).each do |invalid_encoding|
        adapter.content_encoding = invalid_encoding
        expect(adapter.content_encoding).
          to be(proto_dependency_class::ContentEncoding::CONTENT_ENCODING_INVALID)
      end
    end
  end

  describe "#type" do
    it "sets the type correctly" do
      adapter = described_class.new(dependency_file(type: described_class::FILE_TYPE))
      expect(adapter.type).
        to eq(proto_dependency_class::Type::TYPE_FILE)

      adapter = described_class.new(dependency_file(type: described_class::SUBMODULE_TYPE))
      expect(adapter.type).
        to eq(proto_dependency_class::Type::TYPE_SUBMODULE)

      adapter = described_class.new(dependency_file(type: described_class::SYMLINK_TYPE, symlink_target: "~/.dotfiles"))
      expect(adapter.type).
        to eq(proto_dependency_class::Type::TYPE_SYMLINK)
    end

    it "declares the type invalid when appropriate" do
      adapter = described_class.new(dependency_file)

      %w(directory socket something-else).each do |invalid_type|
        adapter.type = invalid_type
        expect(adapter.type).
          to eq(proto_dependency_class::Type::TYPE_INVALID)
      end
    end
  end

  def dependency_file(overrides = {})
    args = {
      content: "all of the content",
      content_encoding: Dependabot::DependencyFile::ContentEncoding::BASE64,
      deleted: false,
      directory: "/.",
      mode: nil,
      name: "Gemfile",
      support_file: false,
      symlink_target: nil,
      type: described_class::FILE_TYPE,
    }.merge(overrides)

    Dependabot::DependencyFile.new(**args)
  end
end
