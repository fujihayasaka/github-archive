# typed: strict
# frozen_string_literal: true

module Dashboard
  class Domain < GH::Domain::Base
    extend T::Sig

    # Find if a user has pinned a repo
    sig { params(repo_id: Integer, user_id: Integer).returns(T::Boolean) }
    def repo_pinned_by_user(repo_id, user_id)
      ::UserDashboardPin.where(pinned_item_type: "Repository", pinned_item_id: repo_id, user_id:).any?
    end
  end
end
