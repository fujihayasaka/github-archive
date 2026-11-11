# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Transfers::TransferFormComponent < ApplicationComponent
  def initialize(sponsorable_login:, stripe_account:)
    @sponsorable_login = sponsorable_login
    @stripe_account = stripe_account
  end

  private

  attr_reader :sponsorable_login, :stripe_account

  def render?
    sponsorable_login.present? && stripe_account.present?
  end

  def manual_transfer_path
    stafftools_sponsors_member_stripe_connect_account_transfers_path(sponsorable_login, stripe_account)
  end
end
