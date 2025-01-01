# typed: true
# frozen_string_literal: true

class Platform::Models::AccountStafftoolsInfo
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def platform_type_name
    # account is expected to be a Bot, User, Organization, or Business
    prefix = if account.is_a?(::Business)
      "Enterprise"
    else
      account.class.name
    end

    "#{prefix}StafftoolsInfo"
  end
end
