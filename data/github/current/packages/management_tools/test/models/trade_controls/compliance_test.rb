# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsComplianceTest < GitHub::TestCase

  fixtures do
    @owner = create(:user, login: "owner")
    @owner_2 = create(:user, login: "owner2")
    @org = create(:organization, admin: @owner)
    @free_org = create(:free_organization, admin: @owner_2)

    @user_1 = create(:user)
    @user_2 = create(:user)
    @user_3 = create(:user)
    @user_4 = create(:user)

    @restricted_user_1 = create(:user, :fully_trade_restricted)
    @restricted_user_2 = create(:user, :fully_trade_restricted)
    @restricted_user_3 = create(:user, :fully_trade_restricted)
  end

  def self.exposes_consistent_interface(subject)
    test "responds to violation?" do
      assert subject.respond_to? :violation?
    end

    test "responds to sdn_suspend?" do
      assert subject.respond_to? :sdn_suspend?
    end

    test "#reason is symbol/string" do
      assert subject.reason.kind_of?(String) ||
        subject.reason.kind_of?(Symbol)
    end

    test "#to_hydro is a Hash" do
      assert_kind_of Hash, subject.to_hydro
    end

    test "responds to full_restriction_violation?" do
      assert subject.respond_to? :full_restriction_violation?
    end

    test "responds to tier_1_restriction_violation??" do
      assert subject.respond_to? :tier_1_restriction_violation?
    end
  end

  context ".for" do
    test "creates an EmailCompliance for an email address" do
      compliance = TradeControls::Compliance.for(email: "foo@example.com")
      assert_kind_of TradeControls::EmailCompliance, compliance
    end

    test "creates an IpCompliance for an ip address" do
      compliance = TradeControls::Compliance.for(ip: "127.0.0.1", location: {})
      assert_kind_of TradeControls::IpCompliance, compliance
    end

    test "creates a ManualCompliance for an actor" do
      compliance = TradeControls::Compliance.for(actor: User.new)
      assert_kind_of TradeControls::ManualCompliance, compliance
    end

    test "creates a WebsiteUrlCompliance for a website url tld" do
      compliance = TradeControls::Compliance.for(organization: @org, website_url: "my-blog.sy")
      assert_kind_of TradeControls::WebsiteUrlCompliance, compliance
    end

    test "creates a NullCompliance as fallback" do
      compliance = TradeControls::Compliance.for
      assert_kind_of TradeControls::NullCompliance, compliance
    end
  end

  context TradeControls::EmailCompliance do
    exposes_consistent_interface TradeControls::EmailCompliance.new(email: "test@example.sy")

    test "#reason is 'email'" do
      compliance = TradeControls::EmailCompliance.new(email: "test@example.sy")
      assert_equal :email, compliance.reason
    end

    test "#to_hydro forms payload hash for publishing to hydro" do
      compliance = TradeControls::EmailCompliance.new(email: "test@example.sy")

      assert_equal({
        reason: :email,
        country: "Syria",
        email: "test@example.sy",
      }, compliance.to_hydro)
    end

    context "#violation?" do
      test "is true for domains: sy, or kp" do
        %w[sy kp].each do |domain|
          compliance = TradeControls::EmailCompliance.new(email: "test@example.#{domain}")
          assert_predicate compliance, :violation?
        end
      end

      test "is not true when email contains sy/kp as substring" do
        %w[sy kp].each do |domain|
          compliance = TradeControls::EmailCompliance.new(email: "test@example.#{domain}.com")
          refute_predicate compliance, :violation?
        end
      end

      test "is true for sanctioned domains" do
        %w[justice.ir moi.ir].each do |domain|
          compliance = TradeControls::EmailCompliance.new(email: "test@#{domain}")
          assert_predicate compliance, :violation?
        end
      end

      test "is true for sanctioned top level domains" do
        tld = ".gov.ir"
        compliance = TradeControls::EmailCompliance.new(email: "test@example#{tld}")
        assert_predicate compliance, :violation?
      end

      test "is not true for sanctioned domain overlap" do
        compliance = TradeControls::EmailCompliance.new(email: "test@anotherjustice.ir.test")
        refute_predicate compliance, :violation?
      end
    end
  end

  context TradeControls::IpCompliance do
    exposes_consistent_interface TradeControls::IpCompliance.new(ip: "IP from Crimea", location: { country_code: "UA", region_name: "Crimea" })

    test "#reason is 'ip'" do
      compliance = TradeControls::IpCompliance.new(ip: "IP from KP", location: { country_code: "KP" })

      assert_equal :ip, compliance.reason
    end

    test "#to_hydro forms payload hash for publishing to hydro" do
      compliance = TradeControls::IpCompliance.new(ip: "IP from Crimea", location: { country_code: "UA", region_name: "Crimea" })

      assert_equal({
        reason: :ip,
        country: "Ukraine",
        region: "Crimea",
        ip: "IP from Crimea",
      }, compliance.to_hydro)
    end

    context "#violation?" do
      test "is false if IP doesn't match sanctioned country" do
        compliance = TradeControls::IpCompliance.new(ip: "IP from UK", location: { country_code: "UK" })

        refute_predicate compliance, :violation?
      end

      test "is true if IP matches sanctioned country" do
        %w[KP SY].each do |code|
          compliance = TradeControls::IpCompliance.new(ip: "IP from #{code}", location: { country_code: code })

          assert_predicate compliance, :violation?
        end
      end

      test "is true if IP matches sanctioned region" do
        compliance = TradeControls::IpCompliance.new(ip: "IP from Crimea", location: { country_code: "UA", region_name: "Crimea" })

        assert_predicate compliance, :violation?
      end

      test "is true if IP matches sanctioned city" do
        compliance = TradeControls::IpCompliance.new(ip: "IP from Makiivka", location: { country_code: "UA", region_name: "Donetsk Oblast", city: "Makiivka" })

        assert_predicate compliance, :violation?
      end

      test "is false if IP is from an unsanctioned city even though the region is sanctioned" do
        compliance = TradeControls::IpCompliance.new(ip: "IP from Unknown", location: { country_code: "UA", region_name: "Donetsk Oblast", city: "Unknown" })

        refute compliance.violation?
      end

      test "is true if IP is from an unsanctioned city even though the country or region is sanctioned" do
        compliance = TradeControls::IpCompliance.new(ip: "IP from Aleppo", location: { country_code: "SY", region_name: "Aleppo Governorate", city: "Aleppo" })

        assert compliance.violation?
      end
    end
  end

  context TradeControls::ManualCompliance do
    exposes_consistent_interface TradeControls::ManualCompliance.new(actor: User.new)

    context "#reason" do
      test "defaults to 'manual'" do
        compliance = TradeControls::ManualCompliance.new(actor: User.new)

        assert_equal :manual, compliance.reason
      end

      test "can be specified" do
        compliance = TradeControls::ManualCompliance.new(actor: User.new, reason: "just because")

        assert_equal "just because", compliance.reason
      end
    end
  end

  context TradeControls::WebsiteUrlCompliance do
    exposes_consistent_interface TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: "my-blog.sy")

    test "#reason is a 'website_url'" do
      compliance = TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: "my-blog.sy")
      assert_equal :website_url, compliance.reason
    end

    test "#to_hydro forms payload hash for publishing to hydro" do
      compliance = TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: "my-blog.sy")

      assert_equal({
        reason: :website_url,
        country: "Syria",
        website_url: "my-blog.sy",
      }, compliance.to_hydro)
    end

    test "#violation? is true for sanctioned tlds: sy, or kp" do
      %w[my-blog.sy/archive http://blog.kp/testing/archives].each do |url|
        compliance = TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: url)
        assert_predicate compliance, :violation?
      end
    end

    test "#violation? is false for non-sanctioned tlds: ir, uk, au, or de" do
      %w[my-blog.ir my-blog.uk my-blog.au/archive http://blog.de/testing/archives].each do |url|
        compliance = TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: url)
        refute_predicate compliance, :violation?
      end
    end

    test "#violation? is false for non valid url tld" do
      # Would throw PublicSuffix::DomainInvalid exception from url_tld if not rescued
      compliance = TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: "test")
      refute_predicate compliance, :violation?
    end

    test "#violation? is false for non valid url tld with space in url" do
      # Would throw URI::InvalidURIError from url_tld if not rescued
      compliance = TradeControls::WebsiteUrlCompliance.new(organization: @org, website_url: "www.test .com")
      refute_predicate compliance, :violation?
    end

    test "#violation? is true for sanctioned domains" do
      compliance = TradeControls::WebsiteUrlCompliance.new(organization: nil, website_url: "www.justice.sy")
      assert_predicate compliance, :violation?
    end

    test "#violation? is false for non valid domain with space in the domain" do
      # Would throw URI::InvalidURIError from url_domain if not rescued
      compliance = TradeControls::WebsiteUrlCompliance.new(organization: nil, website_url: "www.justice .sy")
      refute_predicate compliance, :violation?
    end
  end
end
