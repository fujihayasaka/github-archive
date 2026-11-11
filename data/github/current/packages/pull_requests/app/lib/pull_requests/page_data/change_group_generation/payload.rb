# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ChangeGroupGeneration
  class Payload
    class DiffLineType < T::Enum
      enums do
        CONTEXT = new("CONTEXT")
        ADDITION = new("ADDITION")
        DELETION = new("DELETION")
      end

      sig { params(model_value: PullRequests::ChangeGroup::LineType).returns(DiffLineType) }
      def self.from_model_value(model_value)
        case model_value
        when PullRequests::ChangeGroup::LineType::ADDITION then ADDITION
        when PullRequests::ChangeGroup::LineType::DELETION then DELETION
        when PullRequests::ChangeGroup::LineType::CONTEXT then CONTEXT
        else
          T.absurd(model_value)
        end
      end
    end

    class LatestChangeGroupOrchestrationState < T::Enum
      enums do
        CREATED = new("CREATED")
        STARTED = new("STARTED")
        RUNNING = new("RUNNING")
        SUCCEEDED = new("SUCCEEDED")
        FAILED = new("FAILED")
        SKIPPED = new("SKIPPED")
        WAITING = new("WAITING")
        ABANDONED = new("ABANDONED")
      end
    end

    class UnavailableReason < T::Enum
      enums do
        DIFF_TOO_LARGE = new("DIFF_TOO_LARGE")
        DIFF_TOO_SMALL = new("DIFF_TOO_SMALL")
        TOO_FEW_GROUPS = new("TOO_FEW_GROUPS")
        TOO_MANY_GROUPS = new("TOO_MANY_GROUPS")
        UNABLE_TO_GENERATE = new("UNABLE_TO_GENERATE")
      end

      sig { params(orchestration: T.nilable(PullRequests::Orchestrations::MakeChangeGroups)).returns(T.nilable(UnavailableReason)) }
      def self.for_orchestration(orchestration)
        return nil if orchestration.nil?
        return nil unless orchestration.skipped? || orchestration.failed?

        case reason = orchestration.failure_reason
        when PullRequests::Orchestrations::MakeChangeGroups::FailureReason::DiffTooLarge
          DIFF_TOO_LARGE
        when PullRequests::Orchestrations::MakeChangeGroups::FailureReason::DiffTooSmall
          DIFF_TOO_SMALL
        when PullRequests::Orchestrations::MakeChangeGroups::FailureReason::TooFewGroups
          TOO_FEW_GROUPS
        when PullRequests::Orchestrations::MakeChangeGroups::FailureReason::TooManyGroups
          TOO_MANY_GROUPS
        when PullRequests::Orchestrations::MakeChangeGroups::FailureReason::CompareRepositoryNotFound,
          PullRequests::Orchestrations::MakeChangeGroups::FailureReason::CopilotError,
          PullRequests::Orchestrations::MakeChangeGroups::FailureReason::InvalidGroups,
          PullRequests::Orchestrations::MakeChangeGroups::FailureReason::PromptTooLong,
          PullRequests::Orchestrations::MakeChangeGroups::FailureReason::PullRequestNotFound,
          PullRequests::Orchestrations::MakeChangeGroups::FailureReason::UnknownHunkIDs,
          PullRequests::Orchestrations::MakeChangeGroups::FailureReason::Unknown
          UNABLE_TO_GENERATE
        when nil
          UNABLE_TO_GENERATE
        else
          T.absurd(reason)
        end
      end
    end

    class GroupHunkLine < T::Struct
      const :type, DiffLineType
      const :line, Integer
    end

    class GroupHunk < T::Struct
      const :headerLine, PullRequests::PageData::Diffs::Contents::Payload::DiffLine
      const :startLine, GroupHunkLine
      const :endLine, GroupHunkLine
    end

    class ChangeGroup < T::Struct
      const :id, Integer
      const :name, String
      const :description, T.nilable(String)
      const :priority, Integer
      const :hunkPositions, T::Hash[String, T::Array[GroupHunk]]
    end

    class LatestChangeGroupOrchestration < T::Struct
      const :id, Integer
      const :state, LatestChangeGroupOrchestrationState
    end

    class ChangeGroupGeneration < T::Struct
      const :canAccessChangeGroups, T::Boolean
      const :changeGroupFeedbackOptions, T::Array[T::Hash[Symbol, String]]
      const :changeGroups, T::Array[ChangeGroup]
      const :unavailableReason, T.nilable(UnavailableReason)
      const :latestChangeGroupOrchestration, T.nilable(LatestChangeGroupOrchestration)
      const :changeGroupGenerationChannel, String
    end

    sig { params(data: PullRequests::PageData::ChangeGroupGeneration::Loader::Data).returns(ChangeGroupGeneration) }
    def self.call(data)
      ChangeGroupGeneration.new(
        canAccessChangeGroups: data.can_access_change_groups,
        changeGroupFeedbackOptions: PullRequests::ChangeGroupsFeedback::FEEDBACK_OPTIONS,
        changeGroups: data.change_groups.map do |cg| ChangeGroup.new(
          id: cg.id,
          name: cg.name,
          description: cg.description,
          priority: cg.priority,
          hunkPositions: format_hunk_positions(cg.parsed_hunk_positions),
        )
        end,
        unavailableReason: UnavailableReason.for_orchestration(data.latest_change_group_orchestration),
        latestChangeGroupOrchestration: latest_orchestration(data),
        changeGroupGenerationChannel: data.change_group_generation_channel,
      )
    end

    sig { params(hunk_positions: T::Array[PullRequests::ChangeGroup::HunkPosition]).returns(T::Hash[String, T::Array[GroupHunk]]) }
    private_class_method def self.format_hunk_positions(hunk_positions)
      hunk_positions.each_with_object({}) do |hunk_position, result|
        group_hunk = group_hunk_from(hunk_position)
        next unless group_hunk

        if result[hunk_position.path]
          result[hunk_position.path] << group_hunk
        else
          result[hunk_position.path] = [group_hunk]
        end
      end
    end

    sig { params(hunk_item: PullRequests::ChangeGroup::HunkPosition).returns(T.nilable(GroupHunk)) }
    def self.group_hunk_from(hunk_item)
      hunk_header_text = hunk_item.hunk_header.text
      match = hunk_header_text.match(GitHub::Diff::Enumerator::HUNK_HEADER_PATTERN)

      unless match
        GitHub.logger.info(
          "Invalid hunk header format",
          "code.namespace" => self.name,
          "code.function" => __method__,
        )
        return nil
      end

      left = match[:left].to_i
      right = match[:right].to_i

      GroupHunk.new(
        headerLine: PullRequests::PageData::Diffs::Contents::Payload::DiffLine.new(
          blobLineNumber: right - 1,
          displayNoNewLineWarning: false,
          html: hunk_header_text,
          left: left - 1,
          position: hunk_item.hunk_header.position,
          problems: [],
          right: right - 1,
          text: hunk_header_text,
          type: "HUNK",
        ),
        startLine: GroupHunkLine.new(type: DiffLineType.from_model_value(hunk_item.start_line.type), line: hunk_item.start_line.number),
        endLine: GroupHunkLine.new(type: DiffLineType.from_model_value(hunk_item.end_line.type), line: hunk_item.end_line.number),
      )
    end

    sig { params(data: PullRequests::PageData::ChangeGroupGeneration::Loader::Data).returns(T.nilable(PullRequests::PageData::ChangeGroupGeneration::Payload::LatestChangeGroupOrchestration)) }
    def self.latest_orchestration(data)
      if (orchestration = data.latest_change_group_orchestration)
        LatestChangeGroupOrchestration.new(
          id: orchestration.id,
          state: LatestChangeGroupOrchestrationState.deserialize(orchestration.state.to_s.upcase),
        )
      else
        nil
      end
    end
  end
end
