# typed: strict
# frozen_string_literal: true

module Sponsors
  class UpdateSponsorship
    extend T::Sig

    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # Public: Get a user-friendly message indicating a sponsorship update was successful.
    #
    # sponsor - User or Organization who is sponsoring
    # viewer - the currently authenticated User
    # sponsorable - User or Organization who is receiving the sponsorship
    #
    # Returns a String.
    sig do
      params(
        sponsor: T.any(User, Organization),
        viewer: T.nilable(User),
        sponsorable: T.any(User, Organization)
      ).returns(String)
    end
    def self.success_message(sponsor:, viewer:, sponsorable:)
      sponsor_description = sponsor == viewer ? "Your" : "#{sponsor.safe_profile_name}'s"
      "#{sponsor_description} sponsorship of #{sponsorable.safe_profile_name} has been updated."
    end

    sig { params(sponsorship: Sponsorship, viewer: T.nilable(User)).void }
    def initialize(sponsorship:, viewer:)
      @sponsorship = sponsorship
      @previous_sponsorship = T.let(
        @sponsorship.dup.tap { |s| s.id = @sponsorship.id },
        Sponsorship,
      )
      @viewer = viewer
      @errors = T.let([], T::Array[String])
    end

    protected

    sig { returns(Sponsorship) }
    attr_reader :sponsorship

    sig { returns(T.nilable(User)) }
    attr_reader :viewer

    sig { returns(Sponsorship) }
    attr_reader :previous_sponsorship

    sig { returns(T::Array[String]) }
    attr_reader :errors

    delegate :sponsor, to: :sponsorship

    sig { void }
    def raise_unless_valid
      verify_viewer
      verify_sponsorship_visible
      verify_sponsorship_modifiable
    end

    sig { returns(Sponsorship) }
    def call
      raise_unless_valid
      success = T.let(false, T::Boolean)

      ApplicationRecord::Domain::Sponsors.transaction do
        success = save_sponsorship
        raise ActiveRecord::Rollback unless success
      end

      raise UnprocessableError.new(errors.join(", ")) unless success

      after_sponsorship_saved
      sponsorship
    end

    sig { returns(T::Boolean) }
    def save_sponsorship
      return true unless sponsorship.changed?

      unless sponsorship.save
        errors << "Could not update sponsorship: #{sponsorship.errors.full_messages.join(", ")}"
        return false
      end

      true
    end

    sig { void }
    def after_sponsorship_saved
      # no-op; check child classes
    end

    sig { void }
    def verify_viewer
      raise ForbiddenError.new("Could not update sponsorship") unless viewer
    end

    sig { void }
    def verify_sponsorship_visible
      if sponsorship.nil? || !sponsorship.sponsor_readable_by?(viewer)
        raise ForbiddenError.new("No such sponsorship exists")
      end
    end

    sig { void }
    def verify_sponsorship_modifiable
      return if viewer == User.staff_user

      unless sponsorship.adminable_by?(viewer)
        raise ForbiddenError.new("#{viewer} does not have permission to change #{sponsor}'s sponsorship " \
          "of #{sponsorship.sponsorable_login}")
      end
    end
  end
end
