# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Stack
      module Mergeability
        class Payload
          class State < T::Enum
            enums do
              Mergeable = new("MERGEABLE")
              MergeableIfStatusesPass = new("MERGEABLE_IF_STATUSES_PASS")
              Unknown = new("UNKNOWN")
              Unmergeable = new("UNMERGEABLE")
            end
          end

          class Root < T::Struct
            const :state, State
            const :channels, MergeBox::AliveChannelsPayload::Data
            const :statusCheckChannels, StatusChecksSerializer::StatusCheckAliveChannels
            # Detailed entry status.
            const :entryStatus, T.nilable(MergeBox::MergeRequirementsPayload::StackEntryStatus), default: nil
          end

          sig { params(data: Loader::Data).returns(Root) }
          def self.build(data)
            Root.new(
              state: State.deserialize(data.state.upcase.to_s),
              channels: MergeBox::AliveChannelsPayload.build(
                pull_request: data.pull_request,
                base_repository: data.base_repository,
                head_repository: data.head_repository,
              ),
              statusCheckChannels: StatusChecksSerializer::StatusCheckAliveChannels.build(
                pull_request: data.pull_request,
              ),
              entryStatus: data.entry_status,
            )
          end
        end
      end
    end
  end
end
