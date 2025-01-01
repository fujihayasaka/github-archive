# typed: strict
# frozen_string_literal: true

module SocialAccounts
  # Service object used to update the SocialAccounts associated with a User based on parameters received by a
  # controller. Responsible for verifying feature flag enablement.
  #
  # Double-writes to the #profile_twitter_username column on the User model.
  class AcceptSocialAccountParameters
    include GitHub::Memoizer
    extend T::Sig

    sig { params(user: User, params: ActionController::Parameters).void }
    def self.call(user:, params:)
      new(user:, params:).call
    end

    sig { params(user: User, params: ActionController::Parameters).void }
    def initialize(user:, params:)
      @user = user
      @params = params
    end

    sig { void }
    def call
      if should_use_social_accounts?
        write_from_social_accounts
      elsif should_use_twitter_username?
        write_from_twitter_username
      end
    end

    private

    sig { returns(User) }
    attr_reader :user

    sig { returns(ActionController::Parameters) }
    attr_reader :params

    sig { returns(T.nilable(T::Array[ActionController::Parameters])) }
    memoize def social_account_params
      params[:profile_social_accounts]
    end

    sig { returns(T::Array[SocialAccount]) }
    memoize def incoming_social_accounts
      return [] unless social_account_params
      account_data = T.must(social_account_params).map { |account_param| account_param.permit(:key, :url).to_h }
      existing_social_accounts_by_url = Array(user.profile_social_accounts).index_by(&:url)

      SocialAccount.extract(account_data).filter_map do |account|
        next unless account.url.strip.present?
        existing_social_accounts_by_url.fetch(account.url, account)
      end
    end

    sig { returns(T.nilable(String)) }
    memoize def normalized_twitter_username
      # This is duplicated from User#normalize_profile_twitter_username.
      # It will only be necessary until the double-writing logic is removed.
      params[:profile_twitter_username]&.gsub(/\A@/, "").strip
    end

    sig { returns(T::Boolean) }
    def should_use_social_accounts?
      !!social_account_params
    end

    sig { returns(T::Boolean) }
    def should_use_twitter_username?
      params.has_key?(:profile_twitter_username)
    end

    # Use the :profile_social_accounts POST parameter as the source of truth. Parse its contents and update the
    # social accounts associated with the user's profile, then double-write the first Twitter account to the
    # #profile_twitter_username field.
    sig { void }
    def write_from_social_accounts
      recognition_results = incoming_social_accounts.map do |account|
        account.recognize(defer_expensive: true)
      end
      user.profile_social_accounts = recognition_results.map(&:account)

      if recognition_results.any?(&:deferred)
        RecognizeSocialAccountJob.perform_later(T.must(user.profile&.id))
      end
    end

    # Use the :profile_twitter_username POST parameter as the source of truth. Update the social accounts associated
    # with the user's profile to match.
    sig { void }
    def write_from_twitter_username
      user.profile_twitter_username = params[:profile_twitter_username]
    end
  end
end
