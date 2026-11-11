# typed: strict
# frozen_string_literal: true

class OrcidRecord < ApplicationRecord::Domain::Users
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  destroy_in_background_with :user

  validates :user_id, presence: true, on: :create
  validates :identifier, presence: true

  after_create :enable_metadata_flag, if: :user_id?
  before_destroy :disable_metadata_flag, if: :user_id?
  after_commit :instrument_creation_event, on: :create, if: :user_id?
  after_destroy_commit :instrument_deletion_event, if: :user_id?

  sig { returns(String) }
  def profile_url
    "https://#{GitHub.orcid_host}/#{EscapeUtils.escape_uri_component(identifier)}"
  end

  private

  sig { void }
  def enable_metadata_flag
    set_user_metadata_flag(true)
  end

  sig { void }
  def disable_metadata_flag
    set_user_metadata_flag(false)
  end

  sig { params(value: T::Boolean).void }
  def set_user_metadata_flag(value)
    # Help Sorbet figure out that the user is non-nil for the rest of the method
    u = self.user
    return unless u

    if !u.metadata.destroyed? && u.metadata.has_orcid_record? != value
      u.metadata.update!(has_orcid_record: value)
    end
  end

  sig { void }
  def instrument_creation_event
    return unless user

    GlobalInstrumenter.instrument "orcid_record.create", {
      actor: user,
      identifier: identifier,
    }
  end

  sig { void }
  def instrument_deletion_event
    return unless user

    GlobalInstrumenter.instrument "orcid_record.destroy", {
      actor: user,
      identifier: identifier,
    }
  end
end
