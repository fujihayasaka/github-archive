# typed: false
# frozen_string_literal: true

require "test_helper"

class PageCertificateTest < GitHub::TestCase
  include WebMock::API
  include DogstatsTestHelpers

  ChallengeMock = Struct.new(:status, :filename, :file_content)
  IdentifierMock = Struct.new(:value)
  AuthzMock = Struct.new(:status, :filename, :file_content, :identifier, :url, :http, :certificate)
  HttpMock = Struct.new(:status, :error)
  OrderMock = Struct.new(:authorizations, :url, :certificate, :status)
  fixtures do
    @cert = create(:page_certificate, domain: "www.foo.com")
    @cert_mult_domain = create(:page_certificate, domain: "www.fooabc.com", alt_domain: "fooabc.com")

    # Priate key for Let's Encrypt staging account (ID: 24693628)
    @acme_account_key_string = "-----BEGIN RSA PRIVATE KEY-----\n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\n-----END RSA PRIVATE KEY-----\n"

    @authorization_url = "http://boulder:4000/acme/authz/_fvjdv3Z9KaCjwzJ8BtnArwQVi7Mtn2TmXQZlwJA7lU"
    @challenge_path = ".well-known/acme-challenge/QC-iAujkK1yvfXZyaNJhN3o--q1KBGdNdpXcey7cMF8"
    @challenge_response = "QC-iAujkK1yvfXZyaNJhN3o--q1KBGdNdpXcey7cMF8.uOEBl56QjcixTSwtE_yB-ouxAJPhUAl4US6neNtspXo"

    @alt_authorization_url = "http://boulder:4000/acme/authz/_altdv3ALTaAltkJ8BtnArwQVi7Mtn2TmALTuwJA7lU"
    @alt_challenge_path = ".well-known/acme-challenge/QC-iAujkK1yvfXZyaNJgB3d--w5KBGdNdpXcey7cNQ9"
    @alt_challenge_response = "QC-iAunmU1yvfXZyaNJhN3o--q1KBGwQfpXcey7cMF8.uOEBl12DlcixTSwtE_yB-ouxAJPhUAl4US6neBnjiXo"

    @cert_body = "-----BEGIN CERTIFICATE-----\nMIIFOjCCBCKgAwIBAgITAPqhZFGLp4DxGx5OSS/Os3agpTANBgkqhkiG9w0BAQsF\nADAiMSAwHgYDVQQDDBdGYWtlIExFIEludGVybWVkaWF0ZSBYMTAeFw0yMDA0MjEy\nMjA0MjFaFw0yMDA3MjAyMjA0MjFaMBwxGjAYBgNVBAMMESouZGV2LmF2YWxhbmNo\nLmVzMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApxQ8lKinFX65xIOy\n7uldWXLnqM4g/+4IuQ47KGpy91CFqaTECtKv4leMTGTqF4n2F8E96lZi3vC4x+rF\nNJ8Em73VBlMekoP6ZNTcv29sn5w98r18mEZnzf1oOV8MN9Vq6xr3jU/7xml/Dym7\n1tEfGJgzwB5FstvOu94aOwokDob4v/GKvzfU6yWcFX3qMVP95dZZR0HmUBTuzV3q\nWVauHOl/sUWWrQTnmdK3tlpfhdc2+D9ZXt/ulwIf7c+HcgYskoqhRUcw5JMN+1bi\nXpw9Mm4XbHdVSZSBWANL9bzZ8B6c3VIH7Ax8/COzEwAG3Ndq1EDVvvNr3933nT5C\nTEDD+wIDAQABo4ICbTCCAmkwDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsG\nAQUFBwMBBggrBgEFBQcDAjAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBQT1yWZlNwS\nXs9TOh0txzbrPG8vOjAfBgNVHSMEGDAWgBTAzANGuVggzFxycPPhLssgpvVoOjB3\nBggrBgEFBQcBAQRrMGkwMgYIKwYBBQUHMAGGJmh0dHA6Ly9vY3NwLnN0Zy1pbnQt\neDEubGV0c2VuY3J5cHQub3JnMDMGCCsGAQUFBzAChidodHRwOi8vY2VydC5zdGct\naW50LXgxLmxldHNlbmNyeXB0Lm9yZy8wHAYDVR0RBBUwE4IRKi5kZXYuYXZhbGFu\nY2guZXMwTAYDVR0gBEUwQzAIBgZngQwBAgEwNwYLKwYBBAGC3xMBAQEwKDAmBggr\nBgEFBQcCARYaaHR0cDovL2Nwcy5sZXRzZW5jcnlwdC5vcmcwggEDBgorBgEEAdZ5\nAgQCBIH0BIHxAO8AdQAW6GnB0ZXq18P4lxrj8HYB94zhtp0xqFIYtoN/MagVCAAA\nAXGe/DXBAAAEAwBGMEQCICIDTAFuMR3YqIEUXU9xGX7TyuVjrU/nOvA3LZoaRgdA\nAiBqULdE40IRdw/r1HBZxtbWQk5m42aafQyDpVagYhxNvAB2AMY/IhjDfVamqga1\nltqOU9TXFW0em6yORNIgLeZNadncAAABcZ78N6QAAAQDAEcwRQIgLvEds2lJtQ9f\nmFSU5TKMyy+PhfDVQlnaVhwQOSOahZcCIQDwVE8DgsKs2UvE4aB6jIMif8FNtmep\nbiU50gjVmzURCzANBgkqhkiG9w0BAQsFAAOCAQEAAd0tWaQ8bW3oTjXrlF9RY3ra\njfwUjdlCB6WwA1gAFNgkBB6yOAzz4cFVP7jZl0hvPLQEV14A6/QfjxGDn8Xv9HNJ\nlLUxueCoHCf9RFdy2LZ6Lm1/UN0TBowTI5D+Ts97bZ7urnqA5I7FxD5veeiwJVGy\n6jt97OFqq+i0iJYFoOu30CifR+1mL50XkFzAKPbY5hO834yt0BoNQdgd2Nv+XHW7\nWQIzpH4QQdhEXcAOii0kFdoLlSGCE9+GtLZbWHzyL9uWlNiBHks1Upo4ltJuUY+C\nQMYPQB+urDD94qirATI7WbPWDeFf2FeVSLWG6LHqf9ls8WLEAYb4FprxfH1c4Q==\n-----END CERTIFICATE-----"
    @cert_intermediate_body = "-----BEGIN CERTIFICATE-----\nMIIEqzCCApOgAwIBAgIRAIvhKg5ZRO08VGQx8JdhT+UwDQYJKoZIhvcNAQELBQAw\nGjEYMBYGA1UEAwwPRmFrZSBMRSBSb290IFgxMB4XDTE2MDUyMzIyMDc1OVoXDTM2\nMDUyMzIyMDc1OVowIjEgMB4GA1UEAwwXRmFrZSBMRSBJbnRlcm1lZGlhdGUgWDEw\nggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDtWKySDn7rWZc5ggjz3ZB0\n8jO4xti3uzINfD5sQ7Lj7hzetUT+wQob+iXSZkhnvx+IvdbXF5/yt8aWPpUKnPym\noLxsYiI5gQBLxNDzIec0OIaflWqAr29m7J8+NNtApEN8nZFnf3bhehZW7AxmS1m0\nZnSsdHw0Fw+bgixPg2MQ9k9oefFeqa+7Kqdlz5bbrUYV2volxhDFtnI4Mh8BiWCN\nxDH1Hizq+GKCcHsinDZWurCqder/afJBnQs+SBSL6MVApHt+d35zjBD92fO2Je56\ndhMfzCgOKXeJ340WhW3TjD1zqLZXeaCyUNRnfOmWZV8nEhtHOFbUCU7r/KkjMZO9\nAgMBAAGjgeMwgeAwDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB/wQIMAYBAf8CAQAw\nHQYDVR0OBBYEFMDMA0a5WCDMXHJw8+EuyyCm9Wg6MHoGCCsGAQUFBwEBBG4wbDA0\nBggrBgEFBQcwAYYoaHR0cDovL29jc3Auc3RnLXJvb3QteDEubGV0c2VuY3J5cHQu\nb3JnLzA0BggrBgEFBQcwAoYoaHR0cDovL2NlcnQuc3RnLXJvb3QteDEubGV0c2Vu\nY3J5cHQub3JnLzAfBgNVHSMEGDAWgBTBJnSkikSg5vogKNhcI5pFiBh54DANBgkq\nhkiG9w0BAQsFAAOCAgEABYSu4Il+fI0MYU42OTmEj+1HqQ5DvyAeyCA6sGuZdwjF\nUGeVOv3NnLyfofuUOjEbY5irFCDtnv+0ckukUZN9lz4Q2YjWGUpW4TTu3ieTsaC9\nAFvCSgNHJyWSVtWvB5XDxsqawl1KzHzzwr132bF2rtGtazSqVqK9E07sGHMCf+zp\nDQVDVVGtqZPHwX3KqUtefE621b8RI6VCl4oD30Olf8pjuzG4JKBFRFclzLRjo/h7\nIkkfjZ8wDa7faOjVXx6n+eUQ29cIMCzr8/rNWHS9pYGGQKJiY2xmVC9h12H99Xyf\nzWE9vb5zKP3MVG6neX1hSdo7PEAb9fqRhHkqVsqUvJlIRmvXvVKTwNCP3eCjRCCI\nPTAvjV+4ni786iXwwFYNz8l3PmPLCyQXWGohnJ8iBm+5nk7O2ynaPVW0U2W+pt2w\nSVuvdDM5zGv2f9ltNWUiYZHJ1mmO97jSY/6YfdOUH66iRtQtDkHBRdkNBsMbD+Em\n2TgBldtHNSJBfB3pm9FblgOcJ0FSWcUDWJ7vO0+NTXlgrRofRT6pVywzxVo6dND0\nWzYlTWeUVsO40xJqhgUQRER9YLOLxJ0O6C8i0xFxAMKOtSdodMB3RIwt7RFQ0uyt\nn5Z5MqkYhlMI3J1tPRTp1nEt9fyGspBOO05gi148Qasp+3N+svqKomoQglNoAxU=\n-----END CERTIFICATE-----"
    @pem_chain = [@cert_body, @cert_intermediate_body].join("\n")

    @cert_body_2 = "-----BEGIN CERTIFICATE-----\nMIIFDjBABgkqhkiFREDISGREAThkiG9w0BBQwwDg\n9g73NQbtqZwI+9X5OhpSg/2ALxSalsburyfFZ4yo+\n-----END CERTIFICATE-----"
    @cert_intermediate_body_2 = "-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAJC1HiIAFRIEDCHICKEN3Df\nJjyzfN746vaInA1KxYEeInquisitionzIdj6a7hhphpj2E04\n-----END CERTIFICATE-----"
    @pem_chain_2 = [@cert_body_2, @cert_intermediate_body_2].join("\n")

    @fastly_cert_id = "abcdef123"
  end

  setup do
    Page::Certificate.stubs(:eligible?).returns(true)

    if VCR.turned_on?
      @vcr_turned_off = true
      VCR.turn_off!
    end

    enable_cache_storage
    reset_cache

    @cert.unlock

    @old_raise_on_mismatches = GitHub::Experiment.raise_on_mismatches?
    GitHub::Experiment.raise_on_mismatches = false
  end

  teardown do
    Page::Certificate.unstub(:eligible?)

    VCR.turn_on! if @vcr_turned_off

    disable_cache_storage
    GitHub::Experiment.raise_on_mismatches = @old_raise_on_mismatches
  end

  context ".eligible?" do
    test "returns false for a subdomain of siteleaf.net" do
      Page::Certificate.unstub(:eligible?)
      refute Page::Certificate.eligible?("docs.siteleaf.net")
    end

    test "returns false for a subdomain of streamdata.io" do
      Page::Certificate.unstub(:eligible?)
      refute Page::Certificate.eligible?("projects.api.streamdata.io")
    end
  end

  context ".denylisted?" do
    test "returns true for siteleaf.net" do
      assert Page::Certificate.denylisted?("docs.siteleaf.net"), "siteleaf.net should be denylisted"
    end

    test "returns true for stack.network" do
      assert Page::Certificate.denylisted?("words.stack.network"), "stack.network should be denylisted"
    end

    test "returns true for streamdata.io" do
      assert Page::Certificate.denylisted?("projects.api.streamdata.io"), "streamdata.io should be denylisted"
    end

    test "returns false normally" do
      refute Page::Certificate.denylisted?("ben.balter.com"), "a normal domain name should not be denylisted"
    end
  end

  context "#check_domain" do
    test "raises DomainError if the domain is ineligible" do
      Page::Certificate.stubs(:eligible?).returns(false)
      assert_raises(Page::Certificate::DomainError) do
        @cert.send(:check_domain!)
      end
    end

    test "raises DenylistedError if the domain is denylisted" do
      assert_raises(Page::Certificate::DenylistedError) do
        create(:page_certificate, domain: "docs.siteleaf.net").send(:check_domain!)
      end
    end

    test "raises nothing if the domain is eligible" do
      @cert.send(:check_domain!)
    end
  end

  test "sets initial state" do
    assert_equal :new, @cert.current_state
  end

  test "state order is not modified" do
    #
    # WARNING! MODIFYING THE ORDER WILL INVALIDATE ALL PRODUCTION DATA
    #
    [
      :new,
      :authorization_created,
      :authorization_pending,
      :authorized,
      :authorization_revoked,
      :issued,
      :uploaded,
      :approved,
      :errored,
      :bad_authz,
      :destroy_pending,
      :dns_changed,
      :private_key_revoked
    ]
    .each_with_index do |item, index|
      assert_equal Page::Certificate.states[item], index
    end
  end

  test "state descriptions for each state" do
    Page::Certificate.states.each_key do |state|
      assert_predicate Page::Certificate.state_description(state), :present?
    end
  end

  test "fails to save if no domain" do
    assert_raises(ActiveRecord::RecordInvalid) { create(:page_certificate) } # no domain!
  end

  test "fails to save if domain is modified" do
    @cert.domain = "somethingelse.com"
    assert_raises(Page::Certificate::AttemptedDomainChangeError) { @cert.save }
  end

  test "domain must be unique" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Page::Certificate.create!(domain: @cert.domain)
    end
  end

  test "ACME dance is started upon creation" do
    Page::Certificate.any_instance.expects(:request_authorization).returns(:halt)

    perform_enqueued_jobs(only: [PageCertificateCreateJob, PageCertificateWorkJob]) do
      # Need a page with a matching CNAME, and creating a page will create the associated certificate
      create(:page, cname: "www.otherdomain.com")
    end
  end

  test "smoke test ACME client" do
    VCR.turn_on!
    acme_account_key_pem = OpenSSL::PKey::RSA.new(@acme_account_key_string)
    GitHub.stubs(:acme_account_key).returns(acme_account_key_pem)
    VCR.use_cassette("pages/acme_request_authorization") do
      @cert.request_authorization

      assert_equal @cert.state, "authorization_created"
      assert @cert.authorization_url.starts_with?("https://acme-staging-v02.api.letsencrypt.org/acme/authz-v3/")
    end
  end

  context "#request_authorization" do
    test "good response" do
      set_state(:new)

      challenge = ChallengeMock.new(
        status: "pending",
        filename: @challenge_path,
        file_content: @challenge_response,
      )

      authz = AuthzMock.new(
        identifier: IdentifierMock.new(value: @cert.domain),
        status: "pending",
        url: @authorization_url,
        http: challenge
      )
      order = OrderMock.new(
        authorizations: [authz]
      )
      GitHub.acme.expects(:new_order).with(identifiers: [@cert.domain]).returns(order)

      assert_equal :proceed, @cert.request_authorization
      @cert.reload

      assert_equal(@authorization_url, @cert.authorization_url)
      assert_equal("/#{@challenge_path}", @cert.challenge_path)
      assert_equal(@challenge_response, @cert.challenge_response)
      assert_equal(:authorization_created, @cert.current_state.to_sym)
    end

    test "good response with alternate domain", skip_enterprise: true do
      set_state(:new, has_alt_domain: true)

      challenge_domain = ChallengeMock.new(
        status: "pending",
        filename: @challenge_path,
        file_content: @challenge_response,
      )

      challenge_alt_domain = ChallengeMock.new(
        status: "pending",
        filename: @alt_challenge_path,
        file_content: @alt_challenge_response,
      )

      authz1 = AuthzMock.new(
        identifier: { "type" => "dns", "value" => @cert_mult_domain.domain },
        status: "pending",
        url: @authorization_url,
        http: challenge_domain
      )

      authz2 = AuthzMock.new(
        identifier: { "type" => "dns", "value" => @cert_mult_domain.alt_domain },
        status: "pending",
        url: @alt_authorization_url,
        http: challenge_alt_domain
      )
      order = OrderMock.new(
        authorizations: [authz1, authz2]
      )
      Page::Certificate.expects(:alt_domain_eligible?).returns(true)
      GitHub.acme.expects(:new_order).with(identifiers: [@cert_mult_domain.domain, @cert_mult_domain.alt_domain]).returns(order)

      assert_equal :proceed, @cert_mult_domain.request_authorization
      @cert_mult_domain.reload

      assert_equal(@authorization_url, @cert_mult_domain.authorization_url)
      assert_equal(@alt_authorization_url, @cert_mult_domain.alt_authorization_url)
      assert_equal("/#{@challenge_path}", @cert_mult_domain.challenge_path)
      assert_equal(@challenge_response, @cert_mult_domain.challenge_response)
      assert_equal("/#{@alt_challenge_path}", @cert_mult_domain.alt_challenge_path)
      assert_equal(@alt_challenge_response, @cert_mult_domain.alt_challenge_response)
      assert_equal(:authorization_created, @cert_mult_domain.current_state.to_sym)
    end

    test "bad domain" do
      set_state(:new)

      Page::Certificate.expects(:eligible?).returns(false)

      assert_raises(Page::Certificate::DomainError) do
        @cert.request_authorization
      end

      assert_equal(:new, @cert.current_state.to_sym)
    end
  end

  context "#request_authorization_verification" do
    test "good response" do
      test_key_id = "test.key.id"
      GitHub.stubs(:fastly_private_key_id).returns(test_key_id)
      set_state(:authorization_created)

      authz = AuthzMock.new(
        status: "pending",
        url: @authorization_url,
        http: HttpMock.new
      )

      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)
      authz.http.expects(:request_validation)

      assert_equal(:proceed, @cert.request_authorization_verification)
      assert_equal(:authorization_pending, @cert.current_state.to_sym)
      assert_equal(test_key_id, @cert.fastly_privkey_id)
    end

    test "good response with no alternate domain set", skip_enterprise: true do
      set_state(:authorization_created)

      authz = AuthzMock.new(
        status: "pending",
        url: @authorization_url,
        http: HttpMock.new
      )

      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)
      authz.http.expects(:request_validation)

      assert_equal(:proceed, @cert.request_authorization_verification)
      assert_equal(:authorization_pending, @cert.current_state.to_sym)
    end

    test "good response with an alternate domain set", skip_enterprise: true do
      set_state(:authorization_created, has_alt_domain: true)

      authz = AuthzMock.new(
        status: "pending",
        url: @authorization_url,
        http: HttpMock.new
      )

      alt_authz = AuthzMock.new(
        status: "pending",
        url: @alt_authorization_url,
        http: HttpMock.new
      )

      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)
      GitHub.acme.expects(:authorization).with(url: @alt_authorization_url).returns(alt_authz)
      authz.http.expects(:request_validation)
      alt_authz.http.expects(:request_validation)

      assert_equal(:proceed, @cert_mult_domain.request_authorization_verification)
      assert_equal(:authorization_pending, @cert_mult_domain.current_state.to_sym)
    end

    test "bad domain" do
      set_state(:authorization_created)

      Page::Certificate.expects(:eligible?).returns(false)

      assert_raises(Page::Certificate::DomainError) do
        @cert.request_authorization
      end

      assert_equal(:authorization_created, @cert.current_state.to_sym)
    end
  end

  context "#check_authorization_verification" do
    test "status: valid" do
      test_key_id = "test.key.id"
      GitHub.stubs(:fastly_private_key_id).returns(test_key_id)
      set_state(:authorization_pending)

      authz = AuthzMock.new(
        http: HttpMock.new(
          status: "valid"
        )
      )
      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)

      assert_equal(:proceed, @cert.check_authorization_verification)
      assert_equal(:authorized, @cert.current_state.to_sym)
      assert_equal(test_key_id, @cert.fastly_privkey_id)
    end

    test "status: valid with no alternate domain", skip_enterprise: true do
      set_state(:authorization_pending)

      authz = AuthzMock.new(
        http: HttpMock.new(
          status: "valid"
        )
      )
      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)

      assert_equal(:proceed, @cert.check_authorization_verification)
      assert_equal(:authorized, @cert.current_state.to_sym)
    end

    test "status: valid with an alternate domain", skip_enterprise: true do
      set_state(:authorization_pending, has_alt_domain: true)

      authz = AuthzMock.new(
        http: HttpMock.new(
          status: "valid"
        )
      )
      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)
      GitHub.acme.expects(:authorization).with(url: @alt_authorization_url).returns(authz)
      assert_equal(:proceed, @cert_mult_domain.check_authorization_verification)
      assert_equal(:authorized, @cert_mult_domain.current_state.to_sym)
    end

    test "status: invalid" do
      set_state(:authorization_pending)

      authz = AuthzMock.new(
        status: "invalid",
        http: HttpMock.new(
          status: "invalid",
          error: { "detail" => "bad things" },
        ),
      )

      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)

      assert_equal(:proceed, @cert.check_authorization_verification)
      assert_equal(:bad_authz, @cert.current_state.to_sym)
    end

    test "status: invalid with alternate domain", skip_enterprise: true do
      set_state(:authorization_pending, has_alt_domain: true)

      authz = AuthzMock.new(
        http: HttpMock.new(
          status: "valid"
        )
      )

      authz_invalid = AuthzMock.new(
        status: "invalid",
        http: HttpMock.new(
          status: "invalid",
          error: { "detail" => "bad things" },
        ),
      )

      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz_invalid)
      GitHub.acme.expects(:authorization).with(url: @alt_authorization_url).returns(authz)

      assert_equal(:proceed, @cert_mult_domain.check_authorization_verification)
      assert_equal(:bad_authz, @cert_mult_domain.current_state.to_sym)
    end

    test "status: pending with alternate domains", skip_enterprise: true do
      set_state(:authorization_pending, has_alt_domain: true)

      authz = AuthzMock.new(
        http: HttpMock .new(
          status: "valid"
        )
      )

      authz_pending = AuthzMock.new(
        status: "pending",
        http: HttpMock.new(
          status: "pending"
        )
      )
      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)
      GitHub.acme.expects(:authorization).with(url: @alt_authorization_url).returns(authz_pending)

      assert_equal(:retry, @cert_mult_domain.check_authorization_verification)
      assert_equal(:authorization_pending, @cert_mult_domain.current_state.to_sym)
    end

    test "status: pending" do
      set_state(:authorization_pending)

      authz = AuthzMock.new(
        status: "pending",
        http: HttpMock.new(
          status: "pending"
        )
      )
      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)

      assert_equal(:retry, @cert.check_authorization_verification)
      assert_equal(:authorization_pending, @cert.current_state.to_sym)
    end

    test "status: revoked" do
      set_state(:authorization_pending)

      authz = AuthzMock.new(
        status: "revoked",
        http: HttpMock.new(
          status: "revoked"
        )
      )
      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)

      assert_equal(:proceed, @cert.check_authorization_verification)
      assert_equal(:authorization_revoked, @cert.current_state.to_sym)
    end

    test "status: private_key_revoked flow"  do
      set_state(:approved)

      new_key_id = "a.new.key.id"
      GitHub.stubs(:fastly_private_key_id).returns(new_key_id)

      assert_equal(:proceed, @cert.check_authorization_verification)
      assert_equal(:private_key_revoked, @cert.current_state.to_sym)

      challenge = ChallengeMock.new(
        status: "pending",
        filename: @challenge_path,
        file_content: @challenge_response,
      )

      authz = AuthzMock.new(
        identifier: { "type" => "dns", "value" => @cert.domain },
        status: "pending",
        url: @authorization_url,
        http: challenge
      )
      order = OrderMock.new(
        authorizations: [authz]
      )
      GitHub.acme.expects(:new_order).with(identifiers: [@cert.domain]).returns(order)

      assert_equal :proceed, @cert.request_authorization
      @cert.reload

      assert_equal(@cert.fastly_privkey_id, new_key_id)

      assert_equal(@authorization_url, @cert.authorization_url)
      assert_equal("/#{@challenge_path}", @cert.challenge_path)
      assert_equal(@challenge_response, @cert.challenge_response)
      assert_equal(:authorization_created, @cert.current_state.to_sym)
    end

    test "bad status" do
      set_state(:authorization_pending)

      authz = AuthzMock.new(
        status: "foo",
        http: HttpMock.new(
          status: "foo"
        )
      )
      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)

      assert_equal(:retry, @cert.check_authorization_verification)
      assert_equal(:authorization_pending, @cert.current_state.to_sym)
    end
  end

  context "#request_certificate" do
    test "good response in order valid" do
      set_state(:authorized)

      order = OrderMock.new(
        status: "valid",
        certificate: @pem_chain
      )

      GitHub.acme.expects(:order).returns(order)

      assert_equal(:proceed, @cert.request_certificate)
      assert_equal(:issued, @cert.current_state.to_sym)
      assert_equal(@pem_chain, @cert.send(:parsed_detail)["cert_chain"])
      assert_equal(GitHub.fastly_private_key_id, @cert.fastly_privkey_id)
    end

    test "good response in order ready", skip_enterprise: true do
      set_state(:authorized)
      order = OrderMock.new(
        status: "ready",
      )
      GitHub.acme.expects(:order).returns(order)
      order.expects(:finalize).returns(nil)
      assert_equal(:proceed, @cert.request_certificate)
      assert_equal(:authorized, @cert.current_state.to_sym)
    end

    test "good response in order ready with alternate domain", skip_enterprise: true do
      set_state(:authorized, has_alt_domain: true)
      order = AuthzMock.new(
        status: "ready",
      )
      GitHub.acme.expects(:order).returns(order)
      order.expects(:finalize).returns(nil)
      assert_equal(:proceed, @cert_mult_domain.request_certificate)
      assert_equal(:authorized, @cert_mult_domain.current_state.to_sym)
    end
  end

  context "#upload_certificate" do
    test "update with approved: true" do
      set_state(:issued_update)

      stub_fastly_update_response(approved: true)

      assert_equal(:halt, @cert.upload_certificate)
      assert_equal(:approved, @cert.current_state.to_sym)
      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
    end

    test "update with approved: false" do
      set_state(:issued_update)

      stub_fastly_update_response(approved: false)

      assert_equal(:proceed, @cert.upload_certificate)
      assert_equal(:uploaded, @cert.current_state.to_sym)
      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
    end

    test "update request is rate limited" do
      set_state(:issued_update)
      stub_fastly_update_response(status: 429, approved: false)

      assert_raises(Fastly::CertificateUploadError) { @cert.upload_certificate }

      # If we get rate limited, cert should stay in `:issued`
      # and state detail should remain in the database
      assert_equal(:issued, @cert.current_state.to_sym)
      parsed_chain = JSON.parse(@cert.state_detail)["cert_chain"]
      refute_nil(parsed_chain)
      assert_match(@cert.pem_rexp, parsed_chain)
    end

    test "first upload with approved: true" do
      set_state(:issued_new)

      stub_fastly_upload_response(approved: true)

      assert_equal(:halt, @cert.upload_certificate)
      assert_equal(:approved, @cert.current_state.to_sym)
      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
    end

    test "first upload with approved: false" do
      set_state(:issued_new)

      stub_fastly_upload_response(approved: false)

      assert_equal(:proceed, @cert.upload_certificate)
      assert_equal(:uploaded, @cert.current_state.to_sym)
      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
    end
  end

  context "#check_uploaded_certificate" do
    test "approved: true" do
      set_state(:uploaded)

      stub_fastly_show_response(approved: true)

      assert_equal(:halt, @cert.check_uploaded_certificate)
      assert_equal(:approved, @cert.current_state.to_sym)
      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
    end

    test "approved: false" do
      set_state(:uploaded)

      stub_fastly_show_response(approved: false)

      assert_equal(:retry, @cert.check_uploaded_certificate)
      assert_equal(:uploaded, @cert.current_state.to_sym)
      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
    end
  end

  context "#delete_certificate" do
    test "it works" do
      set_state(:uploaded)

      stub_fastly_delete_response(status: 200)

      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
      assert_nil @cert.delete_certificate

      # This public method should remove the data and update the state of the certificate.
      @cert.reload
      assert_equal :authorization_pending, @cert.current_state.to_sym
      assert_nil @cert.fastly_certificate_id
    end

    test "errors if fastly errors" do
      set_state(:uploaded)

      stub_fastly_delete_response(status: 500)

      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
      assert_raises(Fastly::CertificateDeletionError) { @cert.send(:delete_certificate_from_fastly) }
      assert_equal(@fastly_cert_id, @cert.fastly_certificate_id)
    end
  end

  context "#delete_certificate_from_fastly" do
    test "it fires on certificate deletion" do
      set_state(:approved)

      stub_fastly_delete_response(status: 200)

      @cert.destroy

      assert_empty Page::Certificate.where(id: @cert.id)
    end

    test "errors if fastly errors" do
      set_state(:uploaded)

      stub_fastly_delete_response(status: 500)

      assert_raises(Fastly::CertificateDeletionError) { @cert.destroy }
    end
  end

  context "#needs_renewal?" do
    test "true if expires within our window" do
      @cert.expires_at = 15.days.from_now
      assert @cert.needs_renewal?
    end

    test "true if expired in the past" do
      @cert.expires_at = 2.days.ago
      assert @cert.needs_renewal?
    end

    test "false if expires beyond our window" do
      @cert.expires_at = 45.days.from_now
      refute @cert.needs_renewal?
    end
  end

  context "locking" do
    test "#lock obtains exclusive lock" do
      assert @cert.lock
      refute @cert.lock
    end

    test "#unlock releases exclusive lock" do
      assert @cert.lock
      @cert.unlock
      assert @cert.lock
    end

    test "#with_lock raises if lock cannot be acquired" do
      @cert.lock
      assert_raises(Page::Certificate::LockedError) do
        @cert.with_lock { nil }
      end
    end

    test "#with_lock acquires exclusive lock" do
      @cert.with_lock do
        refute @cert.lock
      end
    end

    test "#with_lock releases exclusive lock" do
      @cert.with_lock { nil }
      assert @cert.lock
    end

    test "#with_lock returns block's return value" do
      assert_equal 123, @cert.with_lock { 123 }
    end

    test "renewal flow verification" do
      # mocking a real page prevents the cert going from
      # :approved -> :destroy_pending when it needs renewal
      user = create(:user, login: "mona")
      repo = create(:repository, owner: user)
      page = create(:page, repository: repo, cname: @cert.domain)
      set_state(:approved)

      Timecop.freeze do
        @cert.update!(expires_at: 10.days.from_now)
      end
      assert @cert.needs_renewal?
      @cert.resume_flow

      authz = AuthzMock.new(
        http: HttpMock.new(
          status: "valid"
        )
      )

      GitHub.acme.expects(:authorization).with(url: @authorization_url).returns(authz)

      perform_enqueued_jobs(only: [PageCertificateWorkJob]) do
        PageCertificateWorkJob.perform_now(@cert.id)
      end

      assert @cert.reload.current_state == :authorized
      assert_dogstats_distribution 1, "pages.certificates.days_before_expiration"
    end

  end

  context "#destroy_certificate" do
    test "it works" do
      set_state(:uploaded)

      stub_fastly_delete_response(status: 200)
      GitHub.fastly.expects(:delete_certificate).with(certificate_id: @cert.fastly_certificate_id)

      assert_equal :halt, @cert.destroy_certificate
      refute Page::Certificate.find_by(id: @cert.id)
    end
  end

  def stub_fastly_upload_response(status: 201, approved: true)
    stub_request(:post, "https://api.fastly.com/tls/5bPJi8MvwBUzRTFXlk5WhX/certificate").
      with(
        headers: {
          "Fastly-Key"   => GitHub.fastly_api_token,
          "Content-Type" => "application/json",
          "Accept"       => "application/json",
        },
        body: {
          "cert"              => @cert_body,
          "cert_intermediate" => @cert_intermediate_body,
          "key_file"          => GitHub.fastly_private_key_id,
          "offset"            => 153,
        }.to_json,
      ).to_return({
        status: status,
        headers: { "Content-Type" => "application/json" },
        body: {
          "cert_id"           => @fastly_cert_id,
          "version"           => 1,
          "cert"              => @cert_body,
          "cert_intermediate" => @cert_intermediate_body,
          "created"           => 1495037664264575497,
          "name"              => "aaaaaaaaaa",
          "key_file"          => GitHub.fastly_private_key_id,
          "cert_file"         => "aaaaaaaaaa.crt",
          "intermediate_file" => "aaaaaaaaaa.intermediate.crt",
          "vhost_file"        => "001-aaaaaaaaaa.conf",
          "offset"            => Fastly::Certificate::FASTLY_PAGES_HTTPS_OFFSET,
          "parse_error"       => "",
          "approved"          => approved,
        }.to_json,
      })
  end

  def stub_fastly_update_response(status: 201, approved: false)
    stub_request(:put, "https://api.fastly.com/tls/5bPJi8MvwBUzRTFXlk5WhX/certificate/#{@fastly_cert_id}").
      with(
        headers: {
          "Accept"          => "application/json",
          "Accept-Encoding" => "gzip;q=1.0,deflate;q=0.6,identity;q=0.3",
          "Content-Type"    => "application/json",
          "Fastly-Key"      => GitHub.fastly_api_token,
          "User-Agent"      => "Faraday v#{Faraday::VERSION}",
        },
        body: {
          "cert"              => @cert_body_2,
          "cert_intermediate" => @cert_intermediate_body_2,
          "key_file"          => GitHub.fastly_private_key_id,
          "offset"            => 153,
        }.to_json,
      ).to_return({
        status: status,
        headers: { "Content-Type" => "application/json" },
        body: {
          "cert_id"           => @fastly_cert_id,
          "version"           => 2,
          "cert"              => @cert_body_2,
          "cert_intermediate" => @cert_intermediate_body_2,
          "created"           => 1495037664264575497,
          "name"              => "bbbbbbbb",
          "key_file"          => GitHub.fastly_private_key_id,
          "cert_file"         => "aaaaaaaaaa.crt",
          "intermediate_file" => "aaaaaaaaaa.intermediate.crt",
          "vhost_file"        => "001-aaaaaaaaaa.conf",
          "offset"            => Fastly::Certificate::FASTLY_PAGES_HTTPS_OFFSET,
          "parse_error"       => "",
          "approved"          => approved,
        }.to_json,
      })
  end

  def stub_fastly_show_response(status: 200, approved: true)
    stub_request(:get, "https://api.fastly.com/tls/5bPJi8MvwBUzRTFXlk5WhX/certificate/#{@fastly_cert_id}").
      with(headers: {
        "Fastly-Key"   => GitHub.fastly_api_token,
        "Content-Type" => "application/json",
        "Accept"       => "application/json",
      }).to_return({
        status: status,
        headers: { "Content-Type" => "application/json" },
        body: {
          "cert_id"           => @fastly_cert_id,
          "version"           => 1,
          "cert"              => @cert_body,
          "cert_intermediate" => @cert_intermediate_body,
          "created"           => 1495037664264575497,
          "name"              => "aaaaaaaaaa",
          "key_file"          => GitHub.fastly_private_key_id,
          "cert_file"         => "aaaaaaaaaa.crt",
          "intermediate_file" => "aaaaaaaaaa.intermediate.crt",
          "vhost_file"        => "001-aaaaaaaaaa.conf",
          "offset"            => Fastly::Certificate::FASTLY_PAGES_HTTPS_OFFSET,
          "parse_error"       => "",
          "approved"          => approved,
        }.to_json,
      })
  end

  def stub_fastly_delete_response(status: 200)
    stub_request(:delete, "https://api.fastly.com/tls/5bPJi8MvwBUzRTFXlk5WhX/certificate/#{@fastly_cert_id}").
      with(headers: {
        "Fastly-Key"   => GitHub.fastly_api_token,
        "Content-Type" => "application/json",
        "Accept"       => "application/json",
      }).to_return({
        status: status,
        headers: { "Content-Type" => "application/json" },
        body:    "{}",
      })
  end

  def set_state(state, has_alt_domain: false)
    case state
    when :new
      @cert.update(
        state: :new,
        expires_at: nil,
        challenge_path: nil,
        challenge_response: nil,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: nil,
        certificate_url: nil,
        state_detail: nil,
      )
      if has_alt_domain
        @cert_mult_domain.update(
          state: :new,
          expires_at: nil,
          challenge_path: nil,
          challenge_response: nil,
          fastly_privkey_id: GitHub.fastly_private_key_id,
          authorization_url: nil,
          certificate_url: nil,
          state_detail: nil,
          alt_challenge_path: nil,
          alt_challenge_response: nil,
          alt_authorization_url: nil
        )
      end
    when :authorization_created
      @cert.update(
        state: :authorization_created,
        expires_at: nil,
        challenge_path: "/#{@challenge_path}",
        challenge_response: @challenge_response,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: @authorization_url,
        certificate_url: nil,
        state_detail: nil,
      )
      if has_alt_domain
        @cert_mult_domain.update(
          state: :authorization_created,
          expires_at: nil,
          challenge_path: "/#{@challenge_path}",
          challenge_response: @challenge_response,
          fastly_privkey_id: GitHub.fastly_private_key_id,
          authorization_url: @authorization_url,
          certificate_url: nil,
          state_detail: nil,
          alt_challenge_path: "/#{@alt_challenge_path}",
          alt_challenge_response: @alt_challenge_response,
          alt_authorization_url: @alt_authorization_url
        )
      end
    when :authorization_pending
      @cert.update(
        state: :authorization_pending,
        expires_at: nil,
        challenge_path: "/#{@challenge_path}",
        challenge_response: @challenge_response,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: @authorization_url,
        certificate_url: nil,
        state_detail: nil,
      )
      if has_alt_domain
        @cert_mult_domain.update(
          state: :authorization_pending,
          expires_at: nil,
          challenge_path: "/#{@challenge_path}",
          challenge_response: @challenge_response,
          fastly_privkey_id: GitHub.fastly_private_key_id,
          authorization_url: @authorization_url,
          certificate_url: nil,
          state_detail: nil,
          alt_challenge_path: "/#{@alt_challenge_path}",
          alt_challenge_response: @alt_challenge_response,
          alt_authorization_url: @alt_authorization_url
        )
      end
    when :authorized
      @cert.update(
        state: :authorized,
        expires_at: nil,
        challenge_path: "/#{@challenge_path}",
        challenge_response: @challenge_response,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: @authorization_url,
        certificate_url: nil,
        state_detail: nil,
      )
      if has_alt_domain
        @cert_mult_domain.update(
          state: :authorized,
          expires_at: nil,
          challenge_path: "/#{@challenge_path}",
          challenge_response: @challenge_response,
          fastly_privkey_id: GitHub.fastly_private_key_id,
          authorization_url: @authorization_url,
          certificate_url: nil,
          state_detail: nil,
          alt_challenge_path: "/#{@alt_challenge_path}",
          alt_challenge_response: @alt_challenge_response,
          alt_authorization_url: @alt_authorization_url
        )
      end
    when :authorization_revoked
      @cert.update(
        state: :authorization_revoked,
        expires_at: 10.days.from_now,
        challenge_path: "/#{@challenge_path}",
        challenge_response: @challenge_response,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: @authorization_url,
        certificate_url: nil,
        state_detail: nil,
      )
    when :issued_new
      @cert.update(
        state: :issued,
        expires_at: 90.days.from_now,
        challenge_path: "/#{@challenge_path}",
        challenge_response: @challenge_response,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: @authorization_url,
        certificate_url: nil,
        state_detail: {
          cert_chain: @pem_chain,
        }.to_json,
      )
    when :issued_update
      @cert.update(
        state: :issued,
        expires_at: 90.days.from_now,
        challenge_path: "/#{@challenge_path}",
        challenge_response: @challenge_response,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: @authorization_url,
        certificate_url: nil,
        fastly_certificate_id: @fastly_cert_id,
        state_detail: {
          cert_chain: @pem_chain_2,
        }.to_json,
      )
    when :uploaded
      @cert.update(
        state: :uploaded,
        expires_at: 90.days.from_now,
        challenge_path: "/#{@challenge_path}",
        challenge_response: @challenge_response,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: @authorization_url,
        certificate_url: nil,
        fastly_certificate_id: @fastly_cert_id,
      )
    when :approved
      @cert.update(
        state: :approved,
        expires_at: 90.days.from_now,
        challenge_path: "/#{@challenge_path}",
        challenge_response: @challenge_response,
        fastly_privkey_id: GitHub.fastly_private_key_id,
        authorization_url: @authorization_url,
        certificate_url: nil,
        fastly_certificate_id: @fastly_cert_id,
      )
    else
      raise "bad state"
    end
  end

end if GitHub.pages_custom_domain_https_enabled?
