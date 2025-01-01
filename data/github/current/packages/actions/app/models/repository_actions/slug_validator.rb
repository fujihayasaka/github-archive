# typed: true
# frozen_string_literal: true

class RepositoryActions::SlugValidator < ActiveModel::Validator
  RESERVED_SLUGS = GitHub::DeniedLogins + %w(action actions agreement category ci manage insight insights delete preview purchases orders colors colors_list icons_list
                                             icons usable_icons usable_colors signature repositories usable_repositories)
  ERROR_MESSAGE = "is unavailable, please change your Action's name"

  def validate(action)
    return unless action.slug

    valid_slug = slug_is_not_reserved_word(action) &&
        slug_is_not_marketplace_category(action) &&
        slug_is_not_existing_user(action) &&
        slug_is_not_existing_org(action)

    unless valid_slug
      action.errors.add(:name, ERROR_MESSAGE)
    end
  end

  private

  def slug_is_not_marketplace_category(action)
    !Marketplace::Category.where(slug: action.slug).exists?
  end

  def slug_is_not_reserved_word(action)
    !RESERVED_SLUGS.include?(action.slug)
  end

  # Private: validate slug does not match an existing User's login
  # - This protects against name squatting
  # - User's can create Actions that match their login
  def slug_is_not_existing_user(action)
    return true if action.owner && (action.owner.login.downcase == action.slug)

    !User.where(login: action.slug, type: "User").exists?
  end

  # Private: validate slug does not match an existing Org login
  # - This protects against name squatting
  # - If user is an owner of the org, then allowed
  def slug_is_not_existing_org(action)
    owner = action.owner

    return true if owner && (owner.login.downcase == action.slug)
    return true if owner && owner.owned_organizations.where(login: action.slug).exists?

    !Organization.where(login: action.slug).exists?
  end
end
