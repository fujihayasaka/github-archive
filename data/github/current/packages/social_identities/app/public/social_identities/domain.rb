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
    sig { params(user_id: Integer).returns(T::Boolean).checked(:always).on_failure(:raise)  }
    def has_social_identity?(user_id)
      social_identities_for_user(user_id).any?
    end

    # Finds all social identities for a user
    sig { params(user_id: Integer).returns(T::Array[Authnd::Proto::SocialIdentityRegistration]).checked(:always).on_failure(:raise)  }
    def social_identities_for_user(user_id)
      return T.must(@social_identities) if defined?(@social_identities)
      resp = self.find_social_identities(user_id)
      return [] if resp.result != :RESULT_SUCCESS
      return [] if resp.social_identity_registrations.empty?

      @social_identities = T.let(resp.social_identity_registrations.to_a, T.nilable(T::Array[Authnd::Proto::SocialIdentityRegistration]))
      @social_identities || []
    end

    # Finds all social identities for a user and returns the Authnd Response object
    sig { params(user_id: Integer).returns(Authnd::Proto::FindSocialIdentitiesResponse).checked(:always).on_failure(:raise) }
    def find_social_identities(user_id)
      social_manager.find_social_identities(user_id)
    end

    # Find one social identity for a user
    sig { params(provider: Integer, subject_id: String, email_id: Integer).returns(Authnd::Proto::FindSocialIdentityResponse).checked(:always).on_failure(:raise) }
    def validate_social_identity(provider, subject_id, email_id)
      social_manager.find_social_identity(provider, subject_id, email_id)
    end

    # Registers a new social identity for a user
    sig { params(provider: Integer, subject_id: String, user_id: Integer, user_email_id: Integer, user_email: String).returns(Authnd::Proto::RegisterSocialIdentityResponse).checked(:always).on_failure(:raise) }
    def register_social_identity(provider, subject_id, user_id, user_email_id, user_email)
      response = social_manager.register_social_identity(provider, subject_id, user_id, user_email_id)

      # Log audit event for social identity linking only if successful
      if response.result == :RESULT_SUCCESS
        instrument_data = {
          user_id: user_id,
          email_id: user_email_id,
          subject_id: subject_id,
          actor_id: user_id,
          provider: SocialLogin::OpenIdConfiguration.provider_value(provider),
          email: user_email
        }

        GitHub.instrument "social_identity.linked", instrument_data
      end

      response
    end

    # Deletes a social identity by user_email_id
    sig { params(user_email_id: Integer, user_email: T.nilable(String)).returns(Authnd::Proto::DeleteSocialIdentityResponse).checked(:always).on_failure(:raise) }
    def delete_social_identity(user_email_id, user_email = nil)
      response = social_manager.delete_social_identity(user_email_id)

      if response.result == :RESULT_SUCCESS
        # Log audit event for social identity unlinking
        GitHub.instrument "social_identity.unlinked", {
          user_email_id: user_email_id,
          email: user_email,
        }
      end

      response
    end

    # Deletes all social identities for a user
    sig { params(user_id: Integer).returns(Authnd::Proto::DeleteSocialIdentitiesResponse).checked(:always).on_failure(:raise) }
    def delete_social_identities(user_id)
      response = social_manager.delete_social_identities(user_id)

      if response.result == :RESULT_SUCCESS
        # Log audit event for all social identities being unlinked
        GitHub.instrument "social_identity.unlinked_all", {
          user_id: user_id,
        }
      end

      response
    end

    # Gets all email IDs that are linked to social identities for a user
    sig { params(user_id: Integer).returns(T::Array[{ email_id: Integer, provider: T.any(Symbol, Integer) }]).checked(:always).on_failure(:raise) }
    def social_linked_email_ids_and_providers(user_id)
      social_identities_for_user(user_id).map { |r| { email_id: r.user_email_id, provider: r.provider } }
    end

    # Determines if the email provided is linked to a social identity
    sig { params(user_id: Integer, email_id: Integer).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def email_is_linked_to_social_identity?(user_id, email_id)
      social_linked_email_ids_and_providers(user_id).any? { |ep| ep[:email_id] == email_id }
    end

    # Retrieves the count of connected social accounts for a given user and provider
    #
    # @param user_id [Integer] The ID of the user
    # @param provider [Integer] The social provider ID (from SocialLogin::OpenIdConfiguration.provider_id)
    # @return [Integer] The number of connected accounts for the specified provider
    sig { params(user_id: Integer, provider: T.any(Symbol, Integer)).returns(Integer).checked(:always).on_failure(:raise) }
    def social_provider_connection_count(user_id, provider)
      begin
        social_links = social_linked_email_ids_and_providers(user_id)
        social_links.count { |link| link[:provider] == provider }
      rescue ::Authnd::Proto::Error, Faraday::Error => e
        # Fallback to 0 if there's an error accessing social identities
        0
      end
    end

    private

    # Defines the social manager used for managing social identities
    sig { returns(::Authnd::Client::SocialIdentityManager) }
    def social_manager
      ::GitHub::Authnd.social_identity_manager("github/account_login")
    end
  end
end
