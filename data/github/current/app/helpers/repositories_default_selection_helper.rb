# typed: strict
# frozen_string_literal: true

module RepositoriesDefaultSelectionHelper
  sig { params(user: User, default_owner: T.nilable(T.any(User, Organization))).returns(T.nilable(T.any(User, Organization))) }
  def default_owner_initial_selection(user, default_owner)
    user_belongs_to_enterprise = user.businesses.any?
    organization_selected_as_owner = default_owner && default_owner.organization?
    force_owner_selection = !organization_selected_as_owner && user_belongs_to_enterprise
    (force_owner_selection || default_owner.nil?) ? nil : default_owner
  end

  sig do
    params(
      user: User,
      default_owner: T.nilable(T.any(User, Organization))
    ).returns(T.nilable(T.any(User, Organization, Repositories::New::OwnerEmptySelectionOption)))
  end
  def default_owner_initial_selection_for_view(user, default_owner)
    default_owner_initial_selection(user, default_owner) || Repositories::New::OwnerEmptySelectionOption.new
  end
end
