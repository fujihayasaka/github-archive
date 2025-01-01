# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Files::FileTree
  class Payload
    include DiffHelper

    # Used in commit range selector only
    class Commit < T::Struct
      const :actorLogin, String
      const :createdAt, String
      const :messageHeadline, String
      const :oid, String
      const :shortOid, String
    end

    module MarkerPosition
      include GitHub::Memoizer

      extend T::Helpers
      interface!
      sealed!

      sig { params(data: Loader::MarkerPosition).returns([MarkerPosition, T.nilable(MarkerPosition::Line)]) }
      def self.convert(data)
        case data
        when Loader::MarkerPosition::File
          [file, nil]
        when Loader::MarkerPosition::Line
          [Line.convert(data), nil]
        when Loader::MarkerPosition::LineRange
          [Line.convert(data.end_line), Line.convert(data.start_line)]
        else
          T.absurd(data)
        end
      end

      sig { returns(File) }
      def self.file
        @file ||= T.let(File.new, T.nilable(File))
      end

      sig { abstract.params(strict: T::Boolean).returns(String) }
      def serialize(strict = true); end

      class Line < T::Struct
        include MarkerPosition

        sig { params(data: Loader::MarkerPosition::Line).returns(Line) }
        def self.convert(data)
          new(
            side: Side.deserialize(data.side),
            line: data.line,
          )
        end

        class Side < T::Enum
          enums do
            Left = new("L")
            Right = new("R")
          end
        end

        const :side, Side
        const :line, Integer

        sig { override.params(strict: T::Boolean).returns(String) }
        def serialize(strict = true) = "#{side.serialize}#{line}"

        sig { returns(String) }
        def to_s = serialize

        sig { params(other: BasicObject).returns(T::Boolean) }
        def eql?(other) = self == other

        sig { params(other: BasicObject).returns(T::Boolean) }
        def ==(other)
          case other
          when Line
            side == other.side && line == other.line
          else
            false
          end
        end

        sig { returns(Integer) }
        def hash = [self.class, side.serialize, line].hash
      end

      class File
        include MarkerPosition

        sig { override.params(strict: T::Boolean).returns(String) }
        def serialize(strict = true) = "FILE"

        sig { returns(String) }
        def to_s = serialize

        sig { params(other: BasicObject).returns(T::Boolean) }
        def eql?(other) = self == other

        sig { params(other: BasicObject).returns(T::Boolean) }
        def ==(other)
          case other
          when File
            true
          else
            false
          end
        end

        sig { returns(Integer) }
        def hash = [self.class, nil].hash
      end
    end

    class Marker < T::Struct
      const :id, Integer
      const :start, T.nilable(MarkerPosition::Line), default: nil
      const :outdatedReason, T.nilable(String), default: nil

      sig { params(options: T.anything).returns(T::Hash[Symbol, T.anything]) }
      def as_json(options = nil)
        result = {}
        result["id"] = id
        result["start"] = start&.serialize
        result["outdatedReason"] = outdatedReason if outdatedReason
        result.compact
      end
    end

    class MarkerCollection < T::Struct
      const :threads, T::Array[Marker], factory: -> { [] }
      const :annotations, T::Array[Marker], factory: -> { [] }
      prop :ctx, T.nilable(T::Range[Integer]), default: nil

      sig { params(range: T.nilable(T::Range[Integer])).void }
      def update_ctx(range)
        return if range.nil?

        if current_ctx = ctx
          self.ctx = ([current_ctx.first, range.first].min)..([current_ctx.last, range.last].max)
        else
          self.ctx = range
        end
      end

      sig { params(options: T.anything).returns(T::Hash[String, T.anything]) }
      def as_json(options = nil)
        result = {}
        result["threads"] = threads.map(&:as_json)
        result["annotations"] = annotations.map(&:as_json)
        if current_ctx = ctx
          result["ctx"] = [current_ctx.first, current_ctx.last]
        end
        result
      end
    end

    class DiffSummary < T::Struct
      const :changeType, Diffs::Entry::ChangeType
      const :isCodeowner, T.nilable(T::Boolean)
      const :isManifestFile, T::Boolean
      const :isVendored, T::Boolean
      const :linesAdded, Integer
      const :linesChanged, Integer
      const :linesDeleted, Integer
      const :markedAsViewed, T::Boolean
      const :path, String
      const :pathDigest, String
      const :highestAnnotationLevel, T.nilable(PullRequests::PageData::Annotations::Payload::AnnotationLevel)
      const :markersMap, T::Hash[MarkerPosition, MarkerCollection]
    end

    class Payload < T::Struct
      const :baseRefOid, String
      const :commits, T::Array[Commit]
      const :diffs, T::Array[DiffSummary]
      const :lastReviewOid, T.nilable(String)
      const :ownerLogin, String
      const :pathName, String
      const :pullRequestId, String
      const :pullRequestNumber, Numeric
      const :repositoryName, String
    end

    sig do
      params(file_tree_data: PullRequests::PageData::Files::FileTree::Loader::Data).returns(Payload)
    end
    def self.call(file_tree_data)
      new.call(file_tree_data)
    end

    sig do
      params(file_tree_data: PullRequests::PageData::Files::FileTree::Loader::Data).returns(Payload)
    end
    def call(file_tree_data)
      Payload.new(
        baseRefOid: file_tree_data.base_ref_oid,
        commits: file_tree_data.commits.map do |commit|
          Commit.new(
            actorLogin: commit.user_display_login,
            createdAt: commit.created_at.iso8601,
            messageHeadline: commit.short_message_text,
            oid: commit.oid,
            shortOid: commit.abbreviated_oid
          )
        end,
        diffs: file_tree_data.diffs.map do |diff|
          DiffSummary.new(
            changeType: diff.change_type,
            isCodeowner: diff.is_codeowner,
            isManifestFile: diff.is_manifest_file,
            isVendored: diff.vendored?,
            linesAdded: diff.lines_added,
            linesChanged: diff.lines_changed,
            linesDeleted: diff.lines_deleted,
            markedAsViewed: file_tree_data.viewed_files.reviewed?(diff.path),
            path: diff.path,
            pathDigest: Digest::SHA256.hexdigest(diff.path),
            highestAnnotationLevel: highest_annotation_level(diff.annotations),
            markersMap: markers_map(
              threads: diff.threads,
              annotations: diff.annotations,
              feature_flags: file_tree_data.feature_flags,
            ),
          )
        end,
        lastReviewOid: file_tree_data.last_review_oid,
        ownerLogin: file_tree_data.repository.owner_display_login,
        pathName: T.must(file_tree_data.pull_request.permalink(include_host: false)),
        pullRequestId: file_tree_data.pull_request.global_relay_id,
        pullRequestNumber: file_tree_data.pull_request.number,
        repositoryName: file_tree_data.repository.name
      )
    end

    sig do
      params(
        threads: T::Enumerable[Loader::ThreadSummary],
        annotations: T::Enumerable[Loader::AnnotationSummary],
        feature_flags: T::Hash[Symbol, T::Boolean],
      ).returns(T::Hash[MarkerPosition, MarkerCollection])
    end
    def markers_map(threads:, annotations:, feature_flags:)
      include_context = feature_flags.fetch(:pull_request_diff_context_injection, false)
      result = T.let({}, T::Hash[MarkerPosition, MarkerCollection])

      threads.each do |thread|
        next if thread.outdated_reason.present?
        end_pos, start_pos = MarkerPosition.convert(thread.position)

        line_markers = (result[end_pos] ||= MarkerCollection.new)
        line_markers.threads << Marker.new(
          id: thread.id,
          start: start_pos,
          outdatedReason: thread.outdated_reason,
        )

        if include_context
          line_markers.update_ctx(thread.position.context_injection_range)
        end
      end

      annotations.each do |annotation|
        end_pos, start_pos = MarkerPosition.convert(annotation.position)

        line_markers = (result[end_pos] ||= MarkerCollection.new)
        line_markers.annotations << Marker.new(
          id: annotation.id,
          start: start_pos,
        )

        if include_context
          line_markers.update_ctx(annotation.position.context_injection_range)
        end
      end

      result
    end

    sig { params(annotation_data: T::Enumerable[Loader::AnnotationSummary]).returns(T.nilable(PullRequests::PageData::Annotations::Payload::AnnotationLevel)) }
    def highest_annotation_level(annotation_data)
      levels = annotation_data.filter_map do |annotation|
        begin
          PullRequests::PageData::Annotations::Payload::AnnotationLevel.deserialize(annotation.level.upcase)
        rescue KeyError
          # TODO: Handle errors properly
          nil
        end
      end

      levels.max
    end
  end
end
