# typed: true
# frozen_string_literal: true

class Discussions::Polls::PreviewsController < Discussions::BaseController

  def create
    poll = DiscussionPollPreviewBuilder.build(
      question: params[:question],
      options: params[:options],
    )

    render(
      Discussions::PollComponent.new(
        discussion_number: discussion&.number,
        repository: current_repository,
        poll: poll,
        options: poll.options,
        preview: true,
        locked: discussion&.locked?
      ),
      layout: false
    )
  end
end
