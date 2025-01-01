# typed: true
# frozen_string_literal: true

module User::StarredCopilotSpacesDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))
    has_many :starred_copilot_spaces, inverse_of: :user
  end

  sig { returns(ActiveRecord::Relation) }
  def ordered_starred_copilot_spaces
    StarredCopilotSpace.where(user: self).order(updated_at: :desc)
  end

  sig { params(copilot_space: CopilotSpace).returns(StarredCopilotSpace) }
  def star_custom_copilot(copilot_space)
    starred_copilot_spaces.create(copilot_space: copilot_space)
  end

  sig { params(starred_copilot_space: StarredCopilotSpace).returns(StarredCopilotSpace) }
  def unstar_custom_copilot(starred_copilot_space)
    starred_copilot_space.destroy
  end
end
