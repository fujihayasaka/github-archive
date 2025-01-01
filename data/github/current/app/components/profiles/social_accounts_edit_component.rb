# typed: strict
# frozen_string_literal: true

module Profiles
  class SocialAccountsEditComponent < ApplicationComponent
    include ProfilesHelper
    include SvgHelper

    ACCOUNT_FIELD_COUNT = 4

    sig { params(this_user: ::User).void }
    def initialize(this_user:)
      @this_user = this_user
    end

    private

    sig { returns(::User) }
    attr_reader :this_user

    sig { returns(T::Array[SocialAccount]) }
    def editable_accounts
      accounts = this_user.profile_social_accounts || []
      (ACCOUNT_FIELD_COUNT - accounts.size).times { accounts << SocialAccount.create(key: "generic", url: "") }
      accounts
    end

    sig { returns(String) }
    def form_name_prefix
      this_user.organization? ? "organization" : "user"
    end
  end
end
