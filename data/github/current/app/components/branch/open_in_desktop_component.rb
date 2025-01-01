# typed: true
# frozen_string_literal: true

class Branch::OpenInDesktopComponent < ApplicationComponent
  include DesktopHelper

  def initialize(repository:, branch_name:)
    @repository = repository
    @branch_name = branch_name
  end

  def clone_url
    app_clone_url(@repository, nil, @branch_name)
  end
end
