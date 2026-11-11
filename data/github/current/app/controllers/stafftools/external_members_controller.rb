# typed: true
# frozen_string_literal: true

class Stafftools::ExternalMembersController < StafftoolsController

  USER_SEARCH_LABELS = {
    "login name" => "login LIKE ?",
  }

  EXTERNAL_IDENTITIES_SEARCH_LABELS = {
    "scim user id" => "guid LIKE ?",
    "external id" => "external_id LIKE ?",
    "saml external id" => "saml_external_id LIKE ?",
    "name id" => "name_id LIKE ?",
    "user name" => "user_name LIKE ?",
  }

  private

  memoize def external_identities_search_by
    if external_identities_search_labels.include?(params[:search])
      params[:search]
    else
      external_identities_search_labels.first
    end
  end
  helper_method :external_identities_search_by

  memoize def unlinked_external_identities_search_by
    if unlinked_external_identities_search_labels.include?(params[:search])
      params[:search]
    else
      unlinked_external_identities_search_labels.first
    end
  end
  helper_method :unlinked_external_identities_search_by

  def external_identities_search_labels
    USER_SEARCH_LABELS.keys + EXTERNAL_IDENTITIES_SEARCH_LABELS.keys
  end
  helper_method :external_identities_search_labels

  def unlinked_external_identities_search_labels
    # unlinked external identities can only be searched by external identity fields
    # cannot use user fields to search for unlinked external identities
    EXTERNAL_IDENTITIES_SEARCH_LABELS.keys
  end
  helper_method :unlinked_external_identities_search_labels

  def external_identity_search
    EXTERNAL_IDENTITIES_SEARCH_LABELS[external_identities_search_by]
  end

  def unlinked_external_identity_search
    EXTERNAL_IDENTITIES_SEARCH_LABELS[unlinked_external_identities_search_by]
  end

  def external_user_search
    USER_SEARCH_LABELS[external_identities_search_by]
  end
end
