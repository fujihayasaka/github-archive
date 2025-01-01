# typed: true
# frozen_string_literal: true

module MoveWorkHelper
  include ActionView::Helpers::TextHelper
  # Public: Display a sentence describing the number of resources to be moved.
  #
  # repos_count    - Total count of repositories to be moved.
  # projects_count - Total count of projects to be moved.
  #
  # Examples
  #
  #   move_work_resources_count_message(1, 0)
  #   # => "1 repository"
  #   move_work_resources_count_message(2, 0)
  #   # => "2 repositories"
  #   move_work_resources_count_message(0, 2)
  #   # => "2 projects"
  #
  # Returns [String] with the sentence.
  def move_work_resources_count_message(repos_count, projects_count)
    repos_message = pluralize(repos_count, "repository") unless repos_count&.zero?
    projects_message = pluralize(projects_count, "project") unless projects_count&.zero?

    to_sentence([repos_message, projects_message].compact)
  end

  def accent_label(feature, plan)
    return :accent if MoveWork::Feature.try_deserialize(feature)&.supported_by_plan?(plan)

    :secondary
  end
end
