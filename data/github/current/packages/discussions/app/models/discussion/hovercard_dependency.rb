# typed: true
# frozen_string_literal: true

module Discussion::HovercardDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  include UserHovercard::SubjectDefinition

  requires_ancestor { Discussion }

  sig { returns T.nilable(Repository) }
  def user_hovercard_parent
    repository
  end

  included do
    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :creator, ->(user, viewer, descendant_subjects:) do
      T.bind(self, Discussion)

      next unless readable_by?(viewer)

      if user_id == user.id
        first_in = if user.discussions.minimum(:id) == self.id
          "(their first ever)"
        elsif user.discussions.for_organization(repository&.organization_id).minimum(:id) == self.id
          "(their first in @#{repository&.organization})"
        elsif user.discussions.for_repository(repository_id).minimum(:id) == self.id
          "(their first in #{repository&.nwo})"
        end

        message = ["Started this discussion", first_in].compact.join(" ")
        Hovercard::Contexts::Custom.new(message, "comment-discussion")
      end
    end
    # rubocop:enable Lint/UnusedBlockArgument
  end
end
