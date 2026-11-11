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
  attr_accessor :commit_sha

  sig { returns(T::Array[ReviewComments::Suggestion::File]) }
  attr_accessor :files

  sig { params(commit_sha: String, files: T::Array[ReviewComments::Suggestion::File]).void }
  def initialize(commit_sha:, files:)
    @commit_sha = commit_sha
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

    commit_sha = T.let(comment_obj["commit_sha"].presence || "", String)
    files = T.let([], T::Array[ReviewComments::Suggestion::File])
    comment_obj["files"].each do |file|
      files.append(ReviewComments::Suggestion::File.new(
        path: file["path"],
        diff_content: file["diff_content"]
      ))
    end

    new(commit_sha:, files:)
  end


  sig { returns(T::Array[GitHub::Diff::Entry]) }
  def diff_entries
    files.each_with_object([]) do |file, out|
      begin
        parser = GitHub::Diff::Parser.new(file.diff_content)
        parser.each do |entry|
          out << entry
        end
      rescue GitHub::Diff::Parser::UnrecognizedText => err
        GitHub.logger.error(
          "Failed to parse diff entry",
          "gh.diff_content": file.diff_content,
          "gh.file_path": file.path,
          "gh.error": err.message
        )

        raise ParseError.new(err.message)
      end
    end
  end

  sig { returns(T::Array[PullRequests::PageData::ThreadComments::Payload::DiffEntry]) }
  def diff_entries_payload
    diff_entries.map do |entry|
      highlighted_lines = DiffEntryHighlighting.new(entry).highlight_lines || []

      lines = []
      entry.each_line.each_with_index do |line, index|
        text = line.text
        if [:addition, :deletion, :context].include?(line.type)
          text = line.text[1..-1].to_s
        end

        lines << PullRequests::PageData::ThreadComments::Payload::DiffLine.new(
          left: line.left,
          right: line.right,
          type: line.type.to_s.upcase,
          html: highlighted_lines[index].presence || text,
          text: text
        )
      end

      PullRequests::PageData::ThreadComments::Payload::DiffEntry.new(diffLines: lines, path: entry.path.to_s)
    end
  end
end
