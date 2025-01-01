# typed: true
# frozen_string_literal: true

class Discussions::CategoryFormSectionsComponent < ApplicationComponent
  extend T::Sig

  sig { params(repository: Repository, category: DiscussionCategory).void }
  def initialize(repository:, category:)
    @repository = repository
    @category = category
  end

  attr_reader :category, :repository

  private

  sig { returns(T::Boolean) }
  def no_section_selected?
    category.discussion_section_id.nil? || category.discussion_section_id.zero?
  end

  sig { params(section: DiscussionSection).returns(T::Boolean) }
  def current_section?(section)
    category.discussion_section_id == section.id
  end
end
