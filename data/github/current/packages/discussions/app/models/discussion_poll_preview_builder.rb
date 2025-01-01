# typed: true
# frozen_string_literal: true

class DiscussionPollPreviewBuilder
  PreviewPoll = Struct.new(:question, :options, :id) do
    sig { returns(T::Boolean) }
    def valid?
      question.present? && options.present?
    end

    sig { returns(Integer) }
    def discussion_poll_votes_count
      0
    end
  end

  PreviewPollOption = Struct.new(:option, :id)

  sig { params(question: T.untyped, options: T.untyped).returns(T.untyped) }
  def self.build(question:, options:)
    preview_options = options.map { |option| PreviewPollOption.new(option) }
    PreviewPoll.new(question, preview_options, true)
  end
end
