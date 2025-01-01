# typed: strict
# frozen_string_literal: true

module SocialAccounts
  # Service object used to update the SocialAccounts associated with a User based on parameters received by a
  # controller.
  class AcceptSocialAccountParameters
    include GitHub::Memoizer

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
      if should_update_social_accounts?
        write_from_social_accounts
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

    sig { returns(T::Boolean) }
    def should_update_social_accounts?
      !!social_account_params
    end

    # Use the :profile_social_accounts POST parameter as the source of truth. Parse its contents and update the
    # social accounts associated with the user's profile.
    sig { void }
    def write_from_social_accounts
      recognition_results = incoming_social_accounts.map do |account|
        account.recognize(defer_expensive: true)
      end
      user.profile_social_accounts = recognition_results.map(&:account)

      if recognition_results.any?(&:deferred)
        RecognizeSocialAccountJob.perform_later(user.profile&.id)
      end
    end
  end
end
