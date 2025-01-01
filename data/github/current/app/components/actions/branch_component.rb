# typed: true
# frozen_string_literal: true

class Actions::BranchComponent < ApplicationComponent
  def initialize(branch:, title:, current_repository:)
    @branch = branch
    @title = title
    @current_repository = current_repository
  end

  def call
    link_to(title,
      tree_path("", branch, current_repository),
      target: "_parent",
      class: "d-inline-block branch-name css-truncate css-truncate-target my-0 my-md-1",
      style: "max-width: 200px;",
      title: title)
  end

  private

  attr_reader :branch, :current_repository, :title
end
