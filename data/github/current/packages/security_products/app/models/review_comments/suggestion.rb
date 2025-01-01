# typed: strict
# frozen_string_literal: true

class ReviewComments::Suggestion
  class Error < StandardError; end
  class ParseError < Error; end

  class File
    sig { returns(String) }
    attr_accessor :path

    sig { returns(String) }
    attr_accessor :diff_content

    sig { params(path: String, diff_content: String).void }
    def initialize(path:, diff_content:)
      @path = path
      @diff_content = diff_content
    end
  end

  sig { returns(String) }
  attr_accessor :description

  sig { returns(T::Array[ReviewComments::Suggestion::File]) }
  attr_accessor :files

  sig { params(description: String, files: T::Array[ReviewComments::Suggestion::File]).void }
  def initialize(description:, files:)
    @description = description
    @files = files
  end

  sig { returns(String) }
  def serialize
    serialized_string = to_json
    compressed = Zlib::Deflate.deflate(serialized_string)
    Base64.strict_encode64(compressed)
  end

  sig { params(base64_json: String).returns(ReviewComments::Suggestion) }
  def self.deserialize(base64_json:)
    compressed = Base64.decode64(base64_json)
    serialized_comment_string = Zlib::Inflate.inflate(compressed)

    comment_obj = JSON.parse(serialized_comment_string)

    description = T.let(comment_obj["description"].presence || "", String)
    files = T.let([], T::Array[ReviewComments::Suggestion::File])
    comment_obj["files"].each do |file|
      files.append(ReviewComments::Suggestion::File.new(
        path: file["path"],
        diff_content: file["diff_content"]
      ))
    end

    new(description: description, files: files)
  end


  sig { returns(T::Array[GitHub::Diff::Entry]) }
  def diff_entries
    begin
      files.each_with_object([]) do |file, out|
        parser = GitHub::Diff::Parser.new(file.diff_content)
        parser.each do |entry|
          out << entry
        end
      end
    rescue GitHub::Diff::Parser::UnrecognizedText => err
      raise ParseError.new(err.message)
    end
  end

  sig { returns(T::Array[PullRequests::PageData::ThreadComments::Payload::DiffEntry]) }
  def diff_entries_payload
    diff_entries.map do |entry|
      lines = []
      entry.each_line do |line|
        lines << PullRequests::PageData::ThreadComments::Payload::DiffLine.new(
          left: line.left,
          right: line.right,
          type: line.type.to_s.upcase,
          html: line.text,
          text: line.text
        )
      end

      PullRequests::PageData::ThreadComments::Payload::DiffEntry.new(diffLines: lines, path: entry.path.to_s)
    end
  end
end
