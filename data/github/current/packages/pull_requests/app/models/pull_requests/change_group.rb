# typed: true
# frozen_string_literal: true

module PullRequests
  class ChangeGroup < ApplicationRecord::Domain::IssuesPullRequests
    include Repositories::BelongsToRepository

    class LineType < T::Enum
      enums do
        ADDITION = new("ADDITION")
        CONTEXT = new("CONTEXT")
        DELETION = new("DELETION")
      end
    end

    MAX_NAME_LENGTH = 48
    HUNK_POSITION_LINE_JSON_SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[type number],
      properties: {
        type: { enum: LineType.values.map(&:serialize) },
        number: { type: "integer", minimum: 1 },
      }
    }.freeze
    HUNK_POSITIONS_JSON_SCHEMA = {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: %w[path hunk_header added_lines removed_lines start_line end_line],
        properties: {
          path: { type: "string" },
          hunk_header: {
            type: "object",
            additionalProperties: false,
            required: %w[text position],
            properties: {
              text: { type: "string" },
              position: { type: "integer", minimum: 0 },
            },
          },
          added_lines: {
            type: "array",
            items: { type: "integer", minimum: 1 },
          },
          removed_lines: {
            type: "array",
            items: { type: "integer", minimum: 1 },
          },
          start_line: HUNK_POSITION_LINE_JSON_SCHEMA,
          end_line: HUNK_POSITION_LINE_JSON_SCHEMA,
        },
      },
    }.freeze

    self.table_name = "pull_request_groups"

    belongs_to_repository_via_domain
    belongs_to :pull_request
    belongs_to :actor, class_name: "User"

    validates :repository, :pull_request, :actor, presence: true
    validates :base_commit_oid, presence: true
    validates :head_commit_oid, presence: true
    validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
    validates :hunk_positions, presence: true
    validate :pull_request_repo_match
    validate :hunk_positions_match_schema

    sig { params(pull: PullRequest).returns(T.all(ActiveRecord::Relation, T::Enumerable[PullRequests::ChangeGroup])) }
    def self.current_for_pull_request(pull)
      all_for_pull_request(pull).where(
        base_commit_oid: pull.base_sha,
        head_commit_oid: pull.head_sha,
      )
    end

    sig { params(pull: PullRequest).returns(T.all(ActiveRecord::Relation, T::Enumerable[PullRequests::ChangeGroup])) }
    def self.all_for_pull_request(pull)
      where(
        repository_id: pull.repository_id,
        pull_request_id: pull.id,
      )
    end

    class HunkHeader < T::Struct
      const :text, String
      const :position, Integer
    end

    class Line < T::Struct
      const :type, LineType
      const :number, Integer
    end

    class HunkPosition
      def initialize(hunk_position)
        @hunk_position = hunk_position
      end

      def path
        @hunk_position["path"]
      end

      def added_lines
        @hunk_position["added_lines"]
      end

      def removed_lines
        @hunk_position["removed_lines"]
      end

      def hunk_header
        HunkHeader.new(
          text: @hunk_position["hunk_header"]["text"],
          position: @hunk_position["hunk_header"]["position"]
        )
      end

      def start_line
        Line.new(
          type: LineType.deserialize(@hunk_position["start_line"]["type"]),
          number: @hunk_position["start_line"]["number"]
        )
      end

      def end_line
        Line.new(
          type: LineType.deserialize(@hunk_position["end_line"]["type"]),
          number: @hunk_position["end_line"]["number"]
        )
      end
    end

    sig { returns(T::Array[HunkPosition]) }
    def parsed_hunk_positions
      hunk_positions.map do |hunk_position|
        HunkPosition.new(hunk_position)
      end
    end

    sig { params(hunk: ChangeGroups::HunkDescription).void }
    def add_hunk_position(hunk)
      added_lines = []
      removed_lines = []

      hunk.lines.each do |line|
        added_lines << line.current if line.addition?
        removed_lines << line.current if line.deletion?
      end
      start_line = hunk.lines.drop_while(&:hunk?).first
      end_line = hunk.lines.last

      if start_line.nil? || end_line.nil?
        raise ArgumentError, "Hunk contained no non-header lines"
      end

      self.hunk_positions ||= []
      self.hunk_positions << {
        path: hunk.file_path,
        hunk_header: {
          text: hunk.header.text,
          position: hunk.header.position,
        },
        added_lines:,
        removed_lines:,
        start_line: {
          type: start_line.type.to_s.upcase,
          number: start_line.current,
        },
        end_line: {
          type: end_line.type.to_s.upcase,
          number: end_line.current,
        },
      }
    end

    private

    def pull_request_repo_match
      if repository_id != pull_request&.repository_id
        errors.add :repository, :mismatch,
          message: "Change group's `repository_id` must match PR's `repository_id`"
      end
    end

    def hunk_positions_match_schema
      validation_errors = ::JSON::Validator.fully_validate(HUNK_POSITIONS_JSON_SCHEMA, hunk_positions)
      validation_errors.each do |message|
        errors.add(:hunk_positions, :json_schema, message:)
      end
    end
  end
end
