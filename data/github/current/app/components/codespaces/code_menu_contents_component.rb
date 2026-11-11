# typed: true
# frozen_string_literal: true

class Codespaces::CodeMenuContentsComponent < ApplicationComponent
  include ApplicationComponent::Rescuable

  DEFAULT_MENU_ITEM_CLASSES = "Box-row Box-row--hover-gray p-3 mt-0"
  DEFAULT_MENU_ITEM_LINK_CLASSES = "d-flex flex-items-center color-fg-default text-bold no-underline"

  attr_reader :visibility, :pull_request, :repository, :ref, :name_param, :is_responsive

  delegate :has_access_to_codespaces?, :repository_policy, to: :visibility

  rescue_from ActiveRecord::ActiveRecordError, with: :nothing

  def initialize(
    visibility:,
    pull_request: nil,
    repository:,
    is_responsive: false
  )
    @pull_request = pull_request
    @repository = repository
    @visibility = visibility
    @is_responsive = is_responsive
  end

  private

  attr_reader :tree_name

  def current_branch_or_tag_name
    if name_param.blank?
      repository.default_branch
    elsif repository.refs.exist?(name_param)
      name_param
    end
  end

  memoize def view
    Repositories::ProtocolSelectorView.new(
      context: :repo_header,
      repository: repository,
      user: current_user,
    )
  end
end
