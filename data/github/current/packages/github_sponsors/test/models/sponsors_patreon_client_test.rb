# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsPatreonClientTest < GitHub::TestCase
  include DogstatsTestHelpers

  context ".get_token" do
    test "returns a hash with the Patreon OAuth response" do
      result = VCR.use_cassette("patreon/get_token") do
        SponsorsPatreonClient.get_token("somecode")
      end

      assert_instance_of Hash, result
      assert_equal "Bearer", result["token_type"]
      assert_equal "someaccesstokenzzz2gk97j9YwALUNu6uUVoYgOaaa", result["access_token"]
      assert_equal "-somerefreshtoken-5gZt8tOZJdHAAkwLOA6aaazzz", result["refresh_token"]
      refute_nil result["expires_in"]
      assert_equal "identity identity[email] campaigns w:campaigns.webhook campaigns.members", result["scope"]
      assert_predicate result["version"], :present?
    end

    test "raises an error when Patreon API response is not successful" do
      error = assert_raises(SponsorsPatreonClient::UnauthorizedError) do
        VCR.use_cassette("patreon/get_token_401") do
          SponsorsPatreonClient.get_token("bad-token")
        end
      end
      assert_equal "Error getting token: invalid_grant", error.message
    end

    test "raises an error when there's a timeout" do
      Faraday::Connection.any_instance.expects(:post).raises(Faraday::TimeoutError, "o noes")

      error = assert_raises(SponsorsPatreonClient::Error) do
        SponsorsPatreonClient.get_token("somecode")
      end

      assert_equal "Error getting token: o noes", error.message
    end

    test "raises when there's an HTTP error" do
      Faraday::Connection.any_instance.expects(:post).raises(Faraday::ServerError, "o noes")

      error = assert_raises(SponsorsPatreonClient::Error) do
        SponsorsPatreonClient.get_token("somecode")
      end

      assert_equal "Error getting token: o noes", error.message
    end
  end

  context ".refresh_token" do
    test "raises an error when Patreon API response is not successful" do
      error = assert_raises(SponsorsPatreonClient::UnauthorizedError) do
        VCR.use_cassette("patreon/refresh_token_401") do
          SponsorsPatreonClient.refresh_token("bad_refresh_token")
        end
      end
      assert_equal "Error refreshing token: invalid_grant", error.message
    end

    test "returns a hash of Patreon response data" do
      result = VCR.use_cassette("patreon/refresh_token") do
        SponsorsPatreonClient.refresh_token("my_refresh_token")
      end

      assert_instance_of Hash, result
      assert_predicate result["access_token"], :present?
      assert_predicate result["refresh_token"], :present?
      refute_nil result["scope"]
      assert_same_elements ["identity", "w:campaigns.benefits", "campaigns.members", "campaigns.members.address",
        "campaigns.members[email]", "campaigns.posts", "w:campaigns.posts", "w:campaigns.webhook",
        "campaigns.webhook", "campaigns", "w:campaigns.apps", "apps.tiers", "identity[email]", "identity.memberships",
        "w:identity.clients"], result["scope"].split(" ")
      assert_equal "Bearer", result["token_type"]
      refute_nil result["expires_in"]
    end

    test "raises an error when there's a timeout" do
      Faraday::Connection.any_instance.expects(:post).raises(Faraday::TimeoutError, "o noes")

      error = assert_raises(SponsorsPatreonClient::Error) do
        SponsorsPatreonClient.refresh_token("sometoken")
      end

      assert_equal "Error refreshing token: o noes", error.message
    end

    test "raises when there's an HTTP error" do
      Faraday::Connection.any_instance.expects(:post).raises(Faraday::ServerError, "o noes")

      error = assert_raises(SponsorsPatreonClient::Error) do
        SponsorsPatreonClient.refresh_token("sometoken")
      end

      assert_equal "Error refreshing token: o noes", error.message
    end
  end

  context ".connection" do
    test "returns a Faraday connection to hit Patreon" do
      result = SponsorsPatreonClient.connection

      assert_instance_of GitHub::FaradayClient::External, result
      assert_equal "#{SponsorsPatreonClient::BASE_PATREON_URL}/", result.url_prefix.to_s
      refute_nil result.headers
      assert_equal "GitHub Sponsors test", result.headers["User-Agent"]
    end
  end

  context "#get_campaigns" do
    test "returns a hash of campaign data for the authorized Patreon user when campaign is published" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")

      result = VCR.use_cassette("patreon/get_campaigns") { client.get_campaigns }

      assert_instance_of Hash, result
      assert_equal 1, result["data"].size
      assert_equal 1, result["meta"]["pagination"]["total"]
      assert_nil result["meta"]["pagination"]["cursors"]["next"]

      campaign_data = result["data"].first
      refute_nil campaign_data
      assert_equal "campaign", campaign_data["type"]
      assert_equal true, campaign_data["attributes"]["is_monthly"]
      assert_equal "2023-08-15T14:50:13.000+00:00", campaign_data["attributes"]["published_at"]
      assert_predicate campaign_data["id"], :present?

      tier_relationships = campaign_data["relationships"]["tiers"]["data"]
      refute_empty tier_relationships
      assert tier_relationships.all? { |tier| tier["type"] == "tier" }
      assert tier_relationships.all? { |tier| tier["id"].present? }

      included_data = result["included"]
      refute_empty included_data
      included_tiers = included_data.select { |data| data["type"] == "tier" }
      assert_equal tier_relationships.size, included_tiers.size
      included_tiers.each do |tier_data|
        assert_predicate tier_data["attributes"]["amount_cents"], :present?
        assert_predicate tier_data["id"], :present?
      end
    end

    test "returns a hash of campaign data for the authorized Patreon user when campaign is unpublished" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")

      result = VCR.use_cassette("patreon/get_campaigns_unpublished") { client.get_campaigns }

      assert_instance_of Hash, result
      assert_equal 1, result["data"].size
      assert_equal 1, result["meta"]["pagination"]["total"]
      assert_nil result["meta"]["pagination"]["cursors"]["next"]

      campaign_data = result["data"].first
      refute_nil campaign_data
      assert_equal "campaign", campaign_data["type"]
      assert_equal true, campaign_data["attributes"]["is_monthly"]
      assert_nil campaign_data["attributes"]["published_at"]
      assert_predicate campaign_data["id"], :present?

      tier_relationships = campaign_data["relationships"]["tiers"]["data"]
      refute_empty tier_relationships
      assert tier_relationships.all? { |tier| tier["type"] == "tier" }
      assert tier_relationships.all? { |tier| tier["id"].present? }

      included_data = result["included"]
      refute_empty included_data
      included_tiers = included_data.select { |data| data["type"] == "tier" }
      assert_equal tier_relationships.size, included_tiers.size
      included_tiers.each do |tier_data|
        assert_predicate tier_data["attributes"]["amount_cents"], :present?
        assert_predicate tier_data["id"], :present?
      end
    end

    test "raises when invalid access token is given" do
      client = SponsorsPatreonClient.new(access_token: "badtoken", refresh_token: "othertoken")

      error = assert_raises(SponsorsPatreonClient::UnauthorizedError) do
        VCR.use_cassette("patreon/get_campaigns_invalid") { client.get_campaigns }
      end

      assert_equal "401 error: The server could not verify that you are authorized to access the URL requested. " \
        "You either supplied the wrong credentials (e.g. a bad password), or your browser doesn't understand how " \
        "to supply the credentials required.", error.message
    end
  end

  context "#get_monthly_campaigns" do
    test "returns a list of monthly campaign hashes for the authorized Patreon user when campaign is published" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")

      result = VCR.use_cassette("patreon/get_campaigns") { client.get_monthly_campaigns }

      assert_equal 1, result.size
      campaign_data = result.first
      assert_instance_of Hash, campaign_data
      assert_equal true, campaign_data["attributes"]["is_monthly"]
      assert_equal "2023-08-15T14:50:13.000+00:00", campaign_data["attributes"]["published_at"]
      assert_equal "10439677", campaign_data["id"]
      assert_equal "campaign", campaign_data["type"]

      patreon_tiers = campaign_data["relationships"]["tiers"]["data"]
      refute_empty patreon_tiers
      assert patreon_tiers.all? { |tier| tier["type"] == "tier" }
      assert patreon_tiers.all? { |tier| tier["id"].present? }
      assert patreon_tiers.all? { |tier| tier["attributes"]["amount_cents"].present? }
      assert patreon_tiers.all? { |tier| tier["attributes"]["published"] }
    end

    test "returns a list of monthly campaign hashes for the authorized Patreon user when campaign is published and tiers are unpublished" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")

      result = VCR.use_cassette("patreon/get_campaigns_with_unpublished_tiers") { client.get_monthly_campaigns }

      assert_equal 1, result.size
      campaign_data = result.first
      assert_instance_of Hash, campaign_data
      assert_equal true, campaign_data["attributes"]["is_monthly"]
      assert_equal "2023-12-13T20:04:04.000+00:00", campaign_data["attributes"]["published_at"]
      assert_equal "10439677", campaign_data["id"]
      assert_equal "campaign", campaign_data["type"]

      patreon_tiers = campaign_data["relationships"]["tiers"]["data"]
      refute_empty patreon_tiers
      assert patreon_tiers.all? { |tier| tier["type"] == "tier" }
      assert patreon_tiers.all? { |tier| tier["id"].present? }
      assert patreon_tiers.all? { |tier| tier["attributes"]["amount_cents"].present? }
      assert_equal true, patreon_tiers.first["attributes"]["published"]
      assert_equal false, patreon_tiers.second["attributes"]["published"]
    end

    test "returns a list of monthly campaign hashes for the authorized Patreon user when campaign is unpublished" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")

      result = VCR.use_cassette("patreon/get_campaigns_unpublished") { client.get_monthly_campaigns }

      assert_equal 1, result.size
      campaign_data = result.first
      assert_instance_of Hash, campaign_data
      assert_equal true, campaign_data["attributes"]["is_monthly"]
      assert_nil campaign_data["attributes"]["published_at"]
      assert_equal "10439677", campaign_data["id"]
      assert_equal "campaign", campaign_data["type"]

      patreon_tiers = campaign_data["relationships"]["tiers"]["data"]
      refute_empty patreon_tiers
      assert patreon_tiers.all? { |tier| tier["type"] == "tier" }
      assert patreon_tiers.all? { |tier| tier["id"].present? }
      assert patreon_tiers.all? { |tier| tier["attributes"]["amount_cents"].present? }
      assert patreon_tiers.all? { |tier| tier["attributes"]["published"] }
    end

    test "returns a list of monthly campaign hashes for the authorized Patreon user when campaign is unpublished and tier is unpublished" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")

      result = VCR.use_cassette("patreon/get_campaigns_unpublished_with_unpublished_tiers") { client.get_monthly_campaigns }

      assert_equal 1, result.size
      campaign_data = result.first
      assert_instance_of Hash, campaign_data
      assert_equal true, campaign_data["attributes"]["is_monthly"]
      assert_nil campaign_data["attributes"]["published_at"]
      assert_equal "10439677", campaign_data["id"]
      assert_equal "campaign", campaign_data["type"]

      patreon_tiers = campaign_data["relationships"]["tiers"]["data"]
      refute_empty patreon_tiers
      assert patreon_tiers.all? { |tier| tier["type"] == "tier" }
      assert patreon_tiers.all? { |tier| tier["id"].present? }
      assert patreon_tiers.all? { |tier| tier["attributes"]["amount_cents"].present? }
      assert_equal true, patreon_tiers.first["attributes"]["published"]
      assert_equal false, patreon_tiers.second["attributes"]["published"]
    end

    test "raises when invalid access token is given" do
      client = SponsorsPatreonClient.new(access_token: "badtoken", refresh_token: "othertoken")

      error = assert_raises(SponsorsPatreonClient::UnauthorizedError) do
        VCR.use_cassette("patreon/get_campaigns_invalid") { client.get_monthly_campaigns }
      end

      assert_equal "401 error: The server could not verify that you are authorized to access the URL requested. " \
        "You either supplied the wrong credentials (e.g. a bad password), or your browser doesn't understand how " \
        "to supply the credentials required.", error.message
    end
  end

  context "#get_memberships" do
    test "returns a list of membership hashes for the specified campaign of the authorized Patreon user" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      campaign_id = "459978"

      result = VCR.use_cassette("patreon/get_memberships") { client.get_memberships(campaign_id) }

      assert_instance_of SponsorsPatreonMemberships, result
      memberships = result.memberships
      assert_equal 100, memberships.size
      assert memberships.all? { |membership| membership["type"] == "member" }
      assert memberships.all? { |membership| membership.dig("relationships", "user", "data", "id").present? }
      assert memberships
        .all? { |membership| membership.dig("attributes", "currently_entitled_amount_cents").present? }
      assert_equal 59, memberships
        .count { |membership| membership.dig("attributes", "patron_status") == "active_patron" }
      assert_equal 96, memberships
        .count { |membership| membership.dig("attributes", "pledge_cadence").present? }
      assert_nil result.next_cursor
      assert_dogstats_timing(1, "#{SponsorsPatreonClient::DATADOG_PREFIX}.get_memberships", tags: ["max_pages:5",
        "first_batch:true"])
    end

    test "respects given page limit" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      campaign_id = "459978"

      result = VCR.use_cassette("patreon/get_memberships") do
        client.get_memberships(campaign_id, max_pages: 1)
      end

      assert_instance_of SponsorsPatreonMemberships, result
      memberships = result.memberships
      assert_equal 20, memberships.size
      assert memberships.all? { |membership| membership["type"] == "member" }
      assert memberships.all? { |membership| membership.dig("relationships", "user", "data", "id").present? }
      assert memberships
        .all? { |membership| membership.dig("attributes", "currently_entitled_amount_cents").present? }
      # Assert that a page can contain all types of memberships
      refute_empty memberships
        .select { |membership| membership.dig("attributes", "patron_status") == "active_patron" }
      refute_empty memberships
        .select { |membership| membership.dig("attributes", "patron_status") == "former_patron" }
      refute_empty memberships
        .select { |membership| membership.dig("attributes", "patron_status") == "declined_patron" }
      # Assert that a page can contain multiple pledge cadences
      refute_empty memberships
        .select { |membership| membership.dig("attributes", "pledge_cadence") == 1 }
      refute_empty memberships
        .select { |membership| membership.dig("attributes", "pledge_cadence") == 12 }
      assert_equal "02B9AS9r0rVy7smJCVpWQPdNob", result.next_cursor
      assert_dogstats_timing(1, "#{SponsorsPatreonClient::DATADOG_PREFIX}.get_memberships", tags: ["max_pages:1",
        "first_batch:true"])
    end

    test "respects given query parameters" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      campaign_id = "459978"

      result = VCR.use_cassette("patreon/get_memberships") do
        client.get_memberships(campaign_id, max_pages: 1, params: {
          SponsorsPatreonClient::PAGE_CURSOR_PARAM => "02B9AS9r0rVy7smJCVpWQPdNob", # 2nd page of results
        })
      end

      assert_instance_of SponsorsPatreonMemberships, result
      memberships = result.memberships
      assert_equal 20, memberships.size
      assert memberships.all? { |membership| membership["type"] == "member" }
      assert memberships.all? { |membership| membership.dig("relationships", "user", "data", "id").present? }
      assert memberships
        .all? { |membership| membership.dig("attributes", "currently_entitled_amount_cents").present? }
      # Assert that page can contain many types of memberships and pledge cadences
      assert_equal 14, memberships
        .count { |membership| membership.dig("attributes", "patron_status") == "active_patron" }
      assert_equal 19, memberships
        .count { |membership| membership.dig("attributes", "pledge_cadence").present? }
      assert_equal "02jhS-NZnu37-sda5AQLsOyoM_", result.next_cursor
      assert_dogstats_timing(1, "#{SponsorsPatreonClient::DATADOG_PREFIX}.get_memberships", tags: ["max_pages:1",
        "first_batch:false"])
    end
  end

  context "#get_active_membership_cents_by_patron_patreon_user_id" do
    test "returns active members of the authenticated Patreon user and the amount they're sponsoring for" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      campaign_id = "459978"

      result = VCR.use_cassette("patreon/get_memberships") do
        client.get_active_membership_cents_by_patron_patreon_user_id(campaign_id)
      end

      assert_instance_of SponsorsPatreonUsersAndAmounts, result
      assert_equal 59, result.amount_in_cents_by_patreon_user_id.size
      assert_equal 100, result.amount_in_cents_by_patreon_user_id["31189703"]
      assert_nil result.next_cursor
    end

    test "returns the monthly amount based on the pledge_cadence" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      campaign_id = "459978"
      yearly_patron_id = "2369915" # Randomly chosen from yearly patrons

      get_memberships_result = VCR.use_cassette("patreon/get_memberships") { client.get_memberships(campaign_id) }
      memberships = get_memberships_result.memberships
      yearly_membership = memberships.find do |membership|
        membership.dig("relationships", "user", "data", "id") == yearly_patron_id
      end

      assert_equal 1762, yearly_membership.dig("attributes", "currently_entitled_amount_cents")
      assert_equal 12, yearly_membership.dig("attributes", "pledge_cadence")

      active_membership_cents_by_patron_patreon_user_id = VCR.use_cassette("patreon/get_memberships") do
        client.get_active_membership_cents_by_patron_patreon_user_id(campaign_id)
      end

      expected_membership_cents = 147 # 1762 / 12
      assert_equal expected_membership_cents, active_membership_cents_by_patron_patreon_user_id.amount_in_cents_by_patreon_user_id["2369915"]
    end

    test "respects the given query parameters and max number of pages to fetch" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      campaign_id = "459978"

      result = VCR.use_cassette("patreon/get_memberships") do
        client.get_active_membership_cents_by_patron_patreon_user_id(campaign_id, params: {
          SponsorsPatreonClient::PAGE_CURSOR_PARAM => "02B9AS9r0rVy7smJCVpWQPdNob", # 2nd page of results
        }, max_pages: 1)
      end

      assert_instance_of SponsorsPatreonUsersAndAmounts, result
      refute_empty result.amount_in_cents_by_patreon_user_id
      assert_equal "02jhS-NZnu37-sda5AQLsOyoM_", result.next_cursor
    end

    test "sums active membership cents for the same patron" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      campaign_id = "123456"
      patron_patreon_user_id = "789"

      fake_memberships_result = SponsorsPatreonMemberships.new(
        memberships: [
          {
            "attributes" => { "currently_entitled_amount_cents" => 100, "patron_status" => "active_patron" },
            "id" => "0094db0b-d0bc-484a-b8bf-049fca5e8380",
            "relationships" => { "user" => { "data" => { "id" => patron_patreon_user_id } } },
            "type" => "member",
          },
          {
            "attributes" => { "currently_entitled_amount_cents" => 200, "patron_status" => "active_patron" },
            "id" => "0094db0b-d0bc-484a-b8bf-049fca5e8381",
            "relationships" => { "user" => { "data" => { "id" => patron_patreon_user_id } } },
            "type" => "member",
          },
        ],
        next_cursor: nil,
      )
      SponsorsPatreonClient.any_instance.expects(:get_memberships).once
        .with(campaign_id, params: {}, max_pages: nil)
        .returns(fake_memberships_result)

      result = client.get_active_membership_cents_by_patron_patreon_user_id(campaign_id)

      assert_equal({ patron_patreon_user_id => 300 }, result.amount_in_cents_by_patreon_user_id)
    end
  end

  context "#get_webhooks" do
    test "returns confirmation when webhooks are configured for given access and refresh tokens" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      triggers = ["members:create", "members:update", "members:delete",
        "members:pledge:create", "members:pledge:update", "members:pledge:delete"]

      result = VCR.use_cassette("patreon/get_webhooks") do
        client.get_webhooks
      end

      assert_instance_of Hash, result
      assert_equal 3, result["data"].size

      last_webhook = result["data"].last["attributes"]

      assert_same_elements triggers, last_webhook["triggers"]
      assert_equal "https://www.github.localhost.com/sponsors/patreon_webhook", last_webhook["uri"]
      assert_equal false, last_webhook["paused"]
    end
  end

  context "#create_webhook" do
    test "returns confirmation when webhook creation succeeded for given campaign_id" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")
      triggers = ["members:create", "members:update", "members:delete",
        "members:pledge:create", "members:pledge:update", "members:pledge:delete"]
      campaign_id = "10439677"

      result = VCR.use_cassette("patreon/create_webhook") do
        client.create_webhook(triggers: triggers, campaign_id: campaign_id, uri: "https://www.github.localhost.com/sponsors/patreon_webhook")
      end

      assert_instance_of Hash, result

      webhook_attributes = result["data"]["attributes"]

      refute_nil webhook_attributes
      assert_same_elements triggers, webhook_attributes["triggers"]
      assert_equal "https://www.github.localhost.com/sponsors/patreon_webhook", webhook_attributes["uri"]
      assert_equal false, webhook_attributes["paused"]
    end

    test "returns confirmation when webhook creation failed for inexistent campaign_id" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "refreshtoken")
      triggers = ["members:create", "members:update", "members:delete",
        "members:pledge:create", "members:pledge:update", "members:pledge:delete"]
      campaign_id = "000"

      VCR.use_cassette("patreon/create_webhook_for_inexistent_campaign") do
        assert_raises_with_message(SponsorsPatreonClient::Error, "400 error: Invalid parameter for 'campaign': resource is missing.") do
          client.create_webhook(triggers: triggers, campaign_id: campaign_id, uri: "https://www.github.localhost.com/sponsors/patreon_webhook")
        end
      end
    end
  end

  context "#delete_webhook" do
    test "hits Patreon API endpoint to delete a webhook" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "othertoken")

      VCR.use_cassette("patreon/delete_webhook") do
        client.delete_webhook("722607")
      end
    end

    test "raises an error when webhook does not exist" do
      client = SponsorsPatreonClient.new(access_token: "D0GbcTtMDzZfoObXscTffMxXQkcYNK_WVGW0eVTjN1I", refresh_token: "tRCHnGOdkX26dyNEh6PyWn-aEDtpAFdAHutDc_IcDqo")
      campaign_id = "10439677"

      assert_raises_with_message(SponsorsPatreonClient::Error, "404 error: webhook with id 0 was not found.") do
        VCR.use_cassette("patreon/delete_webhook_404") do
          client.delete_webhook("0")
        end
      end
    end
  end

  context "#get_identity" do
    test "returns a hash of identity information for the authorized Patreon user" do
      client = SponsorsPatreonClient.new(access_token: "sometoken", refresh_token: "refreshtoken")

      result = VCR.use_cassette("patreon/get_identity") do
        client.get_identity
      end

      assert_instance_of Hash, result
      assert_equal "cheshire137", result["data"]["attributes"]["full_name"]
      assert_equal "cheshire137@github.com", result["data"]["attributes"]["email"]
      assert_equal "88653153", result["data"]["id"]
      assert_equal "user", result["data"]["type"]
      assert_equal "https://www.patreon.com/api/oauth2/v2/user/88653153", result["links"]["self"]
    end

    test "raises unauthorized error when token has expired" do
      client = SponsorsPatreonClient.new(access_token: "oldtoken", refresh_token: "refreshtoken")

      error = assert_raises(SponsorsPatreonClient::UnauthorizedError) do
        VCR.use_cassette("patreon/get_identity_401") do
          client.get_identity
        end
      end

      assert_equal "401 error: The server could not verify that you are authorized to access the URL requested. " \
        "You either supplied the wrong credentials (e.g. a bad password), or your browser doesn't understand how " \
        "to supply the credentials required.", error.message
    end
  end

  context ".raise_for_error_response" do
    test "raises an unauthorized error when HTTP status code is 401" do
      path = "#{SponsorsPatreonClient::PATREON_API_PATH}/v2/identity"
      params = {
        "include" => "campaign",
        "fields[user]" => "full_name,email",
        "fields[campaign]" => "vanity,published_at",
      }
      faraday_err = assert_raises(Faraday::ClientError) do
        VCR.use_cassette("patreon/get_identity_401") { SponsorsPatreonClient.connection.get(path, params) }
      end

      error = assert_raises(SponsorsPatreonClient::UnauthorizedError) do
        SponsorsPatreonClient.raise_for_error_response(faraday_err)
      end
      assert_equal "401 error: The server could not verify that you are authorized to access the URL requested. " \
        "You either supplied the wrong credentials (e.g. a bad password), or your browser doesn't understand how " \
        "to supply the credentials required.", error.message
    end

    test "raises an error when HTTP status code is 400" do
      path = "#{SponsorsPatreonClient::PATREON_API_PATH}/v2/identity"
      params = { "fields[campaign]" => "nope", "include" => "campaign" }
      faraday_err = assert_raises(Faraday::ClientError) do
        VCR.use_cassette("patreon/get_identity_invalid") { SponsorsPatreonClient.connection.get(path, params) }
      end

      error = assert_raises(SponsorsPatreonClient::Error) do
        SponsorsPatreonClient.raise_for_error_response(faraday_err)
      end
      assert_equal "400 error: Invalid parameter for 'fields[campaign]' on type user: ['nope'].", error.message
    end
  end

  test "#auth_url_for_sponsor" do
    state = SecureRandom.hex
    expected_url = "https://www.patreon.com/oauth2/authorize?" \
      "client_id=#{GitHub.patreon_client_id}&" \
      "redirect_uri=#{Rack::Utils.escape(SponsorsPatreonClient::REDIRECT_URL)}&" \
      "response_type=code&" \
      "scope=identity+identity%5Bemail%5D+campaigns+w%3Acampaigns.webhook+campaigns.members&" \
      "state=#{state}"

    assert_equal expected_url, SponsorsPatreonClient.auth_url_for_sponsor(state: state)
  end

  test "#auth_url_for_sponsorable" do
    state = SecureRandom.hex
    expected_url = "https://www.patreon.com/oauth2/authorize?" \
      "client_id=#{GitHub.patreon_client_id}&" \
      "redirect_uri=#{Rack::Utils.escape(SponsorsPatreonClient::REDIRECT_URL)}&" \
      "response_type=code&" \
      "scope=identity+identity%5Bemail%5D+campaigns+w%3Acampaigns.webhook+campaigns.members&" \
      "state=#{state}"

    assert_equal expected_url, SponsorsPatreonClient.auth_url_for_sponsorable(state: state)
  end

  test "#become_patreon_url" do
    state = SecureRandom.hex
    expected_url = "https://www.patreon.com/oauth2/become-patron?" \
      "campaign_id=123&" \
      "client_id=#{GitHub.patreon_client_id}&" \
      "min_cents=100&" \
      "redirect_uri=#{Rack::Utils.escape(SponsorsPatreonClient::REDIRECT_URL)}&" \
      "response_type=code&" \
      "scope=identity+identity%5Bemail%5D+campaigns+w%3Acampaigns.webhook+campaigns.members&" \
      "state=#{state}"

    assert_equal expected_url, SponsorsPatreonClient.become_patreon_url(campaign_id: "123", state: state, min_cents: 100)
  end
end
