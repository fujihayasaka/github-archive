# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiscussionPollOptionOrderField < Platform::Enums::Base
      description "Properties by which discussion poll option connections can be ordered."

      visibility :public, environments: [:dotcom, :enterprise]

      value "AUTHORED_ORDER", "Order poll options by the order that the poll author specified when creating the poll.", value: "id"
      value "VOTE_COUNT", "Order poll options by the number of votes it has.", value: "discussion_poll_votes_count"
    end
  end
end
