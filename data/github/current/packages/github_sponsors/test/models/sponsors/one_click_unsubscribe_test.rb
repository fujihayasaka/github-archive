# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::OneClickUnsubscribeTest < GitHub::TestCase
  skip_unless :sponsors_enabled?

  fixtures do
    @sponsorable = create(:user, :sponsorable)
    @subscribed_sponsorship = create(:sponsorship, sponsorable: @sponsorable)
    @subscribed_sponsor = @subscribed_sponsorship.sponsor
    @subscribed_org_sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
    @subscribed_org_sponsor = @subscribed_org_sponsorship.sponsor
  end

  context "#headers" do
    test "generates headers for user sponsor" do
      one_click = Sponsors::OneClickUnsubscribe.new(sponsor: @subscribed_sponsor, sponsorable: @sponsorable)
      headers = one_click.headers
      assert_equal("List-Unsubscribe=One-Click", headers["List-Unsubscribe-Post"])
      list_unsubscribe_match = /^\<(?<url>.*)\>$/.match(headers.fetch("List-Unsubscribe"))
      list_unsubscribe_url = list_unsubscribe_match && list_unsubscribe_match["url"]
      parsed_url = URI.parse(T.must(list_unsubscribe_url))
      assert_equal "https", parsed_url.scheme
      assert_equal GitHub.host_name, parsed_url.host
      assert_match %r{/sponsors/one-click-unsubscribe/\w+}, parsed_url.path
    end

    test "generates headers for org sponsor" do
      one_click = Sponsors::OneClickUnsubscribe.new(sponsor: @subscribed_org_sponsor, sponsorable: @sponsorable)
      headers = one_click.headers
      assert_equal("List-Unsubscribe=One-Click", headers["List-Unsubscribe-Post"])
      list_unsubscribe_match = /^\<(?<url>.*)\>$/.match(headers.fetch("List-Unsubscribe"))
      list_unsubscribe_url = list_unsubscribe_match && list_unsubscribe_match["url"]
      parsed_url = URI.parse(T.must(list_unsubscribe_url))
      assert_equal "https", parsed_url.scheme
      assert_equal GitHub.host_name, parsed_url.host
      assert_match %r{/sponsors/one-click-unsubscribe/\w+}, parsed_url.path
    end
  end

  context ".process_token" do
    test "processes token for user sponsor" do
      token = valid_token(sponsor: @subscribed_sponsor, sponsorable: @sponsorable)
      assert_predicate @subscribed_sponsorship, :is_sponsor_opted_in_to_email?
      Sponsors::OneClickUnsubscribe.process_token(token)
      refute_predicate @subscribed_sponsorship.reload, :is_sponsor_opted_in_to_email?
    end

    test "processes token for org sponsor" do
      token = valid_token(sponsor: @subscribed_org_sponsor, sponsorable: @sponsorable)
      assert_predicate @subscribed_org_sponsorship, :is_sponsor_opted_in_to_email?
      Sponsors::OneClickUnsubscribe.process_token(token)
      refute_predicate @subscribed_org_sponsorship.reload, :is_sponsor_opted_in_to_email?
    end

    test "ignores already unsubscribed sponsor" do
      token = valid_token(sponsor: @subscribed_sponsor, sponsorable: @sponsorable)
      assert_predicate @subscribed_sponsorship, :is_sponsor_opted_in_to_email?

      Sponsors::OneClickUnsubscribe.process_token(token)

      refute_predicate @subscribed_sponsorship.reload, :is_sponsor_opted_in_to_email?
    end

    test "ignores invalid token scope" do
      token = GitHub::Authentication::SignedAuthToken.generate(
        user: @subscribed_org_sponsor,
        scope: "invalid_scope",
        expires: 10.years.from_now,
        data: { m_id: @sponsorable.id }
      )
      assert_predicate @subscribed_org_sponsorship, :is_sponsor_opted_in_to_email?

      Sponsors::OneClickUnsubscribe.process_token(token)

      assert_predicate @subscribed_org_sponsorship.reload, :is_sponsor_opted_in_to_email?
    end

    test "ignores invalid token" do
      token = "INVALID_TOKEN"
      Sponsors::OneClickUnsubscribe.process_token(token)
    end
  end

  def valid_token(sponsor:, sponsorable:)
    GitHub::Authentication::SignedAuthToken.generate(
      user: sponsor,
      scope: "sponsors_newsletter_unsubscribe",
      expires: 10.years.from_now,
      data: { m_id: sponsorable.id }
    )
  end
end
