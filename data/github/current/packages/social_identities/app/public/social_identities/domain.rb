# typed: strict
# frozen_string_literal: true

module SocialIdentities
  class Domain < GH::Domain::Base
    # Declare @social_identities as a nilable instance variable
    sig { returns(T.nilable(T::Array[Authnd::Proto::SocialIdentityRegistration])) }
    attr_reader :social_identities

    # Determines if the user has a social identity linked to their account.
    #
    # @param user_id [Integer] The ID of the user to check.
    # @param user [T.nilable(User)] The user object, if available. If not provided, the method will fetch social identities for the user ID.
    # @return [Boolean] True if the user has a social identity, false otherwise.
    sig { params(user_id: Integer, user: T.nilable(User)).returns(T::Boolean).checked(:always).on_failure(:raise)  }
    def has_social_identity?(user_id, user: nil)
      user&.feature_enabled?(:temp_social_identity_user) || social_identities_for_user(user_id).any?
    end

    # Finds all social identities for a user
    sig { params(user_id: Integer).returns(T::Array[Authnd::Proto::SocialIdentityRegistration]).checked(:always).on_failure(:raise)  }
    def social_identities_for_user(user_id)
      return T.must(@social_identities) if defined?(@social_identities)
      resp = social_manager.find_social_identities(user_id)
      return [] if resp.result != :RESULT_SUCCESS
      return [] if resp.social_identity_registrations.empty?

      @social_identities = T.let(resp.social_identity_registrations.to_a, T.nilable(T::Array[Authnd::Proto::SocialIdentityRegistration]))
      @social_identities || []
    end

    # Find one social identity for a user
    sig { params(provider: Integer, subject_id: String, email_id: Integer).returns(Authnd::Proto::FindSocialIdentityResponse).checked(:always).on_failure(:raise) }
    def validate_social_identity(provider, subject_id, email_id)
      social_manager.find_social_identity(provider, subject_id, email_id)
    end

    # Registers a new social identity for a user
    sig { params(provider: Integer, subject_id: String, user_id: Integer, user_email_id: Integer).returns(Authnd::Proto::RegisterSocialIdentityResponse).checked(:always).on_failure(:raise) }
    def register_social_identity(provider, subject_id, user_id, user_email_id)
      social_manager.register_social_identity(provider, subject_id, user_id, user_email_id)
    end

    # Deletes a social identity by user_email_id
    sig { params(user_email_id: Integer).returns(Authnd::Proto::DeleteSocialIdentityResponse).checked(:always).on_failure(:raise) }
    def delete_social_identity(user_email_id)
      social_manager.delete_social_identity(user_email_id)
    end

    # Deletes all social identities for a user
    sig { params(user_id: Integer).returns(Authnd::Proto::DeleteSocialIdentitiesResponse).checked(:always).on_failure(:raise) }
    def delete_social_identities(user_id)
      social_manager.delete_social_identities(user_id)
    end

    private

    # Defines the social manager used for managing social identities
    sig { returns(::Authnd::Client::SocialIdentityManager) }
    def social_manager
      ::GitHub::Authnd.social_identity_manager("github/account_login")
    end
  end
end
