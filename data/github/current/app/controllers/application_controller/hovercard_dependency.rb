# typed: false
# frozen_string_literal: true

module ApplicationController::HovercardDependency
  extend ActiveSupport::Concern

  included do
    helper_method :hovercard_subject_tag
  end

  attr_reader :hovercard_subject_tag

  def set_hovercard_subject(subject)
    prefix = Hovercard.prefix_for(subject)

    if prefix
      @hovercard_subject_tag = "#{prefix}:#{subject.id}"
    end
  end
end
