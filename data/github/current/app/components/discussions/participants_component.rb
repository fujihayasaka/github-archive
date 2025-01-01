# typed: true
# frozen_string_literal: true

module Discussions
  class ParticipantsComponent < ApplicationComponent
    MAX_AVATARS = Discussions::BaseController::MAX_AVATARS

    delegate :discussion_view_click_attrs, to: :helpers

    def initialize(discussion:, participants:, participant_count:)
      @discussion = discussion
      @participants = participants
      @participant_count = participant_count
    end

    private

    attr_reader :discussion, :participants, :participant_count

    memoize def total_participant_count
      participant_count = discussion.participant_count(viewer: current_user)
      pluralize(number_with_delimiter(participant_count), "participant")
    end

    memoize def capped_participants
      participants.first(MAX_AVATARS)
    end

    def show_more_text?
      participant_count > MAX_AVATARS
    end
  end
end
