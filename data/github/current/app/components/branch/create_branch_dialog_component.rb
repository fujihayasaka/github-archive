# typed: true
# frozen_string_literal: true

class Branch::CreateBranchDialogComponent < ApplicationComponent

  def initialize(src:, show:, label: "Create a branch")
    @src = src
    @show = show
    @label = label
  end

  def show_dialog?
    @show
  end

  def src
    @src
  end

  def label
    @label
  end
end
