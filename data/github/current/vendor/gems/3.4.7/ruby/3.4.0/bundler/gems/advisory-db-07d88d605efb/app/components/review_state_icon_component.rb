# frozen_string_literal: true

class ReviewStateIconComponent < ApplicationComponent
  include HasCurationState

  attr_reader :curation_state, :octicon_args

  def initialize(review: nil, curation_state: review.curation_state, **octicon_args)
    @curation_state = curation_state
    @octicon_args = octicon_args
  end

  def call
    render IconComponent.new(
      icon: curation_state_icon(curation_state),
      color: curation_state_color(curation_state),
      title: curation_state_label(curation_state),
      **octicon_args,
    )
  end
end
