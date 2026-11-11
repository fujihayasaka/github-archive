# typed: strict
# frozen_string_literal: true

class TradeControls::LegalNotification
  include UrlHelpers

  TRUST_AND_SAFETY_FORM_ID = 360000288072
  TRUST_AND_SAFETY_GROUP_ID = 360003703111

  sig { params(kwargs: T.untyped).void }
  def self.create_for_sponsors_maintainer(**kwargs)
    new(**T.unsafe(kwargs)).create_for_sponsors_maintainer
  end

  sig { params(account: T.any(User, Organization, Business)).void }
  def initialize(account:)
    @account = account
  end

  sig { void }
  def create_for_sponsors_maintainer
    account.send_sponsors_maintainer_restricted_email
    create_zendesk_ticket
  end

  private

  sig { void }
  def create_zendesk_ticket
    CreateZendeskTicket.perform_later \
      "Trade Controls",
      "traderestrictions@noreply.github.com",
      "Sponsors - SDN True Match",
      zendesk_body,
      brand_id: GitHub.zendesk_brand_id,
      custom_fields: zendesk_custom_fields,
      tags: zendesk_tags,
      ticket_form_id: TRUST_AND_SAFETY_FORM_ID,
      group_id: TRUST_AND_SAFETY_GROUP_ID
  end

  sig { returns(String) }
  def zendesk_body
    body = <<~BODY
      #{account.display_login} has been identified as a true match through SDN screening, and is currently a sponsored maintainer in the
      sponsors program.
    BODY
  end

  sig { returns(T::Hash[String, String]) }
  def zendesk_custom_fields
    {
      GitHub.zendesk_fields[:login] => account.display_login,
      GitHub.zendesk_fields[:level] => "level_2",
      GitHub.zendesk_fields[:category] => "cat_ts_trade_restrictions"
    }
  end

  sig { returns(T::Array[String]) }
  def zendesk_tags
    %w[squad_compliance]
  end

  sig { returns(T.any(User, Organization, Business)) }
  attr_reader :account
end
