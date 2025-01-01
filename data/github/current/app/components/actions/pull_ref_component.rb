# typed: true
# frozen_string_literal: true

class Actions::PullRefComponent < ApplicationComponent
  def initialize(ref:)
    @ref = ref
  end

  def call
    content_tag :span, ref, class: "d-inline-block branch-name css-truncate css-truncate-target my-0 my-md-1", style: "max-width: 200px;"
  end

  private

  attr_reader :ref
end
