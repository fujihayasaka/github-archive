# typed: strict
# frozen_string_literal: true

# User model extensions relevant to GitHub's integration with ORCID, an identity service for academic researchers.
# See https://orcid.org/.
module User::OrcidDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_one :orcid_record, dependent: :destroy
  end

  # Efficiently determine whether or not this User has an OrcidRecord without trying to load the association. Checks
  # a boolean field on UserMetadata, instead, because that association is already loaded everywhere we need to
  # determine this.
  #
  # The UserMetadata field is kept accurate by ActiveRecord lifecycle callbacks on the OrcidRecord model.
  #
  # Returns a Boolean telling the caller if it's worth trying to load the #orcid_record association or not.
  sig { returns(T::Boolean) }
  def has_orcid_record?
    # Short-circuit without any queries for non-User subclasses.
    return false unless user?

    metadata.has_orcid_record?
  end

  # Public access to the UserSetting field that determines whether or not a User wants an associated ORCID
  # identifier displayed on their profile. Defaults to true.
  sig { returns(T::Boolean) }
  def display_orcid_id_on_profile?
    settings.get(:display_orcid_id_on_profile)
  end

  # Public access to set whether or not a User wants an associated ORCID identifier to be displayed on their
  # public profile.
  sig { params(value: T::Boolean).void }
  def display_orcid_id_on_profile=(value)
    old_value = display_orcid_id_on_profile?
    settings.set!(:display_orcid_id_on_profile, value)
    if old_value != value
      GlobalInstrumenter.instrument("orcid_display_preference.change", actor: self, value:)
    end
  end
end
