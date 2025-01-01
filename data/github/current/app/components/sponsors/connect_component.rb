# typed: true
# frozen_string_literal: true

class Sponsors::ConnectComponent < ApplicationComponent
  extend T::Sig

  delegate :social_account_icon, to: :helpers

  sig { params(user: User, text: String, url: String).void }
  def initialize(user:, text: "", url: "")
    @user = user
    @text = text
    @url = url
  end

  sig { returns(User) }
  attr_reader :user

  sig { returns(String) }
  attr_reader :text, :url

  private

  sig { returns T::Array[SocialAccount] }
  def shareable_social_accounts
    social_accounts = user.profile_social_accounts

    return [] if social_accounts.nil?

    social_accounts.select do |social_account|
      !share_url_by_social_account(social_account).nil?
    end
  end

  sig { params(social_account: SocialAccount).returns(T.nilable(String)) }
  def share_url_by_social_account(social_account)
    social_account.url
  end
end
