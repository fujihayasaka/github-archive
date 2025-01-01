# typed: true
# frozen_string_literal: true

require "test_helper"

if !GitHub.enterprise?
  class EnterpriseInstallationUserAccountsImporterTest < GitHub::TestCase
    include UploadableTestHelpers
    include HydroTestHelpers

    fixtures do
      @admin = create(:paid_user)
      @org   = create(:organization, admin: @admin)
      @business = create(:business, owners: [@admin], organizations: [@org])
      @business_installation = create(:enterprise_installation, owner: @business)
      @upload = create :enterprise_installation_user_accounts_upload,
        business: @business
      save_file_for_uploadable @upload,
        name: "github-localhost-20190319115623.json",
        size: 1.megabyte,
        content_type: "application/json"
      @accounts_data = Rails.root.join("test/fixtures/enterprise_installations/user_accounts_export.json").read
      @license_data = Rails.root.join("test/fixtures/github-enterprise-utf8.ghl").read
      @license = GitHub::Connect::Authenticator.new.load_license(@license_data).freeze
      # This is a hack to catch an unexplained occurrence of flaky failures which only
      # occurs on CI which no one has been able to figure out. If we encounter the
      # "Too many open files" error, @license will be nil.
      # See https://github.com/github/github/issues/149951 and https://github.com/github/admin-experience/issues/934
      skip if @license.nil?
    end

    setup do
      @importer = create_importer
      EnterpriseInstallationUserAccountsUpload.any_instance.
        stubs(:download_and_read_file).returns(@accounts_data)
    end

    context "::parse_user_accounts_data" do
      test "raises ArgumentError when data is nil" do
        assert_raises ArgumentError do
          EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data nil
        end
      end

      test "raises ArgumentError when data is invalid JSON" do
        assert_raises ArgumentError do
          EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data "I AM NOT JSON"
        end
      end

      test "raises error when data is not a user accounts export" do
        data = <<~JSON
          {
            "foo": "bar"
          }
        JSON
        assert_raises EnterpriseInstallationUserAccountsImporter::InvalidDataError do
          EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data data
        end
      end

      test "returns a Hash corresponding to valid JSON" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "github.localhost"
            },
            "users": [
              {
                "user_id": 12345,
                "created_at": "2019-03-11 21:19:53",
                "login": "octocat",
                "profile_name": "The Octocat",
                "site_admin": true,
                "emails": [
                  {
                    "email": "octocat@github.com",
                    "primary": true
                  },
                  {
                    "email": "another@example.com"
                  }
                ]
              }
            ]
          }
        JSON
        result = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data data
        assert_equal 1, result[:version]
        assert_equal "github.localhost", result[:instance][:hostname]
        assert_equal 1, result[:users].size
      end

      test "decrypts data" do
        message = "w+b11vnRZwaAo5wKgwJDrXDT9ir/787WDa9ls2D+PmXh2NyQ+jTXMqrhjdgx\nS+Fd278VPffzl7NmU1DX2w9P\n"
        assert_equal ["Hello world"], EnterpriseInstallationUserAccountsImporter.send(:decrypt_data, message)
      end

      test "raises error when attempting to decrypt GPG encrypted data" do
        message = "-----BEGIN PGP MESSAGE-----\n\njA0EBwMC9n4hf3E58Nfk0ukBzMUGHSQgexWWjrvtDauCWbbW2lxcbyhMfhxMGhQ+\ncLHkATp64c7nTekBLRq0W2JNhFjrInEw2K6Uc/NV6SELP4UShcwuwrA6fbvj0z2R\nBOM/hb8m0+TIbcIKc1laLqtvPdlDNv93aXDMc6URYCRVnV++e6JHd71pz1iRrysH\nFu5buzvQ4or7YtdOjTyVygksT8LJz3fu/EJhMrhYo9i+hCQKw3ztR6VJJLTipgYj\nmnPLl/YT2WKvjA1n9mUMX+k7/VIJ6zHD1b0ztJD3Q5qLj90I5kOLQwLIv5GO2B4S\n2FQrQVRi7Ng/nmeh/xWHNfE2mD4vFMXs2Hp1+LLe39eJdVyBDLQ0U9eawn3DRcdI\n0yPc27JvUdVCiovBfq2FXOdDa8DT6VJxNv6Tgzrv02ks62lqpR0BXRcvFEuzmD0w\nkFep06+f+wkaEgju3FMNZ6PYTYo9cPBAHNoQivgcAIw0Y1D0OdCzCohcFh5n1GEw\nU4xYo7PhWn+7JIZZ5ZRRRiZzI73Un5pnK8kVnFp3JVqf7iPu6/3nF0Wmsak+duZK\nRN02lpxVQ2N6YxbTqsGDJlP3CJ52zsXOhOwcMcwyTGpMokxYvO8ve26B39io+zTn\nbrp0E0W4VCs3Kkb8CSrGYbpFjR2B5R5h+BScc72R64Aiq1tyjWRLAI1d+oFCmCfZ\nnMCz1LooEw1/VWTvLD7/wI6OZjPw7V/Masv7AAH2pXY+ZCa0JBmxKDVu/yLDWR7a\nBuzzUYySetarivXOPQycYh/6IcnD53FtlB6pJtYT1gCXG418QLmd3uNiBugd90Sq\n0lIfpkKFPsX0dHorEXjXa6AzN4SMkEwxXwU+a0rMEku6GGwNyaCfCDryW8lUaF0N\naojCOBhC6tgbFd/K5y4vr+zNI9uQziKoUKz+9o8WnGGjs8drQYSa+n1Xi4upBDZA\neq/6voiQVeQhOH2bmXIh6k4bqpBcrl2wB+DTPJogvGp0ZNYh1wORJ3+tBLBdJuRT\nCyt4Y0fgg+HMxeMmnkyvTDxQ/8qtOZ6DnyDIHQUdvhaPZjq1/Q1S5UOS9HNB4SNS\n1ts6DCokWP5Jx/hrPphB0CQ317s09WAdJgVC7itI2M1/l6LGm6o/9h6ot3nXYyuu\niPf08PZA3Y2fKc5vIudUuXFn5LWcPCJ01oG4Kc9Xf1jUqVbdzCU=\n=CkxZ\n-----END PGP MESSAGE-----\n"
        assert_raises(EnterpriseInstallationUserAccountsImporter::UnsupportedEncryptionError) do
          EnterpriseInstallationUserAccountsImporter.send(:decrypt_data, message)
        end
      end
    end

    context "#synchronize_user_accounts_data!" do
      test "adds new EnterpriseInstallationUserAccounts included in JSON" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          # Expect @accounts_data fixture to include two accounts that are added
          @importer.synchronize_user_accounts_data!
        end
        assert_equal accounts_hash[:users].size, @business_installation.user_accounts.size

        first = @business_installation.user_accounts.find_by \
          remote_user_id: accounts_hash[:users][0][:user_id]
        assert_account_synced_from_hash(accounts_hash[:users][0], first)
        second = @business_installation.user_accounts.find_by \
          remote_user_id: accounts_hash[:users][1][:user_id]
        assert_account_synced_from_hash(accounts_hash[:users][1], second)
      end

      test "creates a new EnterpriseInstallation for the business when no installation provided" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "EnterpriseInstallation.count", 1 do
            # Expect @accounts_data fixture to include two accounts that are added
            importer = create_importer installation: nil
            importer.synchronize_user_accounts_data!
          end
        end
        installation = EnterpriseInstallation.where(owner: @business).last
        assert_equal accounts_hash[:users].size, T.must(installation).user_accounts.size
        # Upload should be associated with newly created installation
        assert_equal installation, @upload.reload.enterprise_installation
      end

      test "looks up customer name from license when creating new EnterpriseInstallation" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        server_id = SecureRandom.uuid
        accounts_hash[:instance][:server_id] = server_id
        accounts_hash[:instance][:license] = Base64.encode64(@license_data)
        with_encoded_license = JSON.generate accounts_hash
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(with_encoded_license)

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "EnterpriseInstallation.count", 1 do
            importer = create_importer installation: nil
            importer.synchronize_user_accounts_data!
          end
        end
        installation = EnterpriseInstallation.where(owner: @business).where(server_id: server_id).last
        assert_equal @license.company, T.must(installation).customer_name
      end

      test "falls back to business name for customer name when creating new EnterpriseInstallation" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        accounts_hash[:instance][:license] = "Not a Base64-encoded license string"
        with_encoded_license = JSON.generate accounts_hash
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(with_encoded_license)

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "EnterpriseInstallation.count", 1 do
            importer = create_importer installation: nil
            importer.synchronize_user_accounts_data!
          end
        end
        installation = EnterpriseInstallation.where(owner: @business).last
        assert_equal @business.name, T.must(installation).customer_name
      end

      test "looks up license_public_key from license when creating new EnterpriseInstallation" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        server_id = SecureRandom.uuid
        accounts_hash[:instance][:server_id] = server_id
        accounts_hash[:instance][:license] = Base64.encode64(@license_data)
        with_encoded_license = JSON.generate accounts_hash
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(with_encoded_license)

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "EnterpriseInstallation.count", 1 do
            importer = create_importer installation: nil
            importer.synchronize_user_accounts_data!
          end
        end
        installation = EnterpriseInstallation.where(owner: @business).where(server_id: server_id).last
        assert_equal \
          Base64.decode64(@license.customer_public_key),
          T.must(installation).license_public_key
      end

      test "falls back to an empty string for license_public_key when creating new EnterpriseInstallation" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        accounts_hash[:instance][:license] = "Not a Base64-encoded license string"
        with_encoded_license = JSON.generate accounts_hash
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(with_encoded_license)

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "EnterpriseInstallation.count", 1 do
            importer = create_importer installation: nil
            importer.synchronize_user_accounts_data!
          end
        end
        installation = EnterpriseInstallation.where(owner: @business).last
        assert_equal "", T.must(installation).license_public_key
      end

      test "finds an existing EnterpriseInstallation owned by the business based on the server_id included in the upload" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        server_id = accounts_hash[:instance][:server_id]
        installation = create :enterprise_installation, owner: @business, server_id: server_id
        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_no_difference "EnterpriseInstallation.count" do
            # Expect @accounts_data fixture to include two accounts that are added
            importer = create_importer installation: nil
            importer.synchronize_user_accounts_data!
          end
        end
        assert_equal accounts_hash[:users].size, installation.user_accounts.size
        # Upload should be associated with existing installation that was found
        assert_equal installation, @upload.reload.enterprise_installation
      end

      test "does not fail for users without a primary email" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "github.localhost"
            },
            "users": [
              {
                "user_id": 54321,
                "created_at": "2019-03-10 07:19:53",
                "login": "eviljdennes",
                "profile_name": "Herr Evil",
                "site_admin": true,
                "emails": [
                  {
                    "email": "evil@evil.io"
                  },
                  {
                    "email": "not-primary-evil@evil.io"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)
        assert_nothing_raised do
          @importer.synchronize_user_accounts_data!
        end
      end

      test "does not fail for users with only user_id and email information" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "github.localhost"
            },
            "users": [
              {
                "user_id": 54321,
                "emails": [
                  {
                    "email": "evil@evil.io",
                    "primary": true
                  },
                  {
                    "email": "not-primary-evil@evil.io"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)
        assert_nothing_raised do
          assert_difference "EnterpriseInstallationUserAccount.count", 1 do
            assert_no_difference "EnterpriseInstallation.count" do
              @importer.synchronize_user_accounts_data!
            end
          end
        end
        account = T.must(EnterpriseInstallation.where(owner: @business).last).user_accounts.first
        assert_equal T.must(account).remote_user_id, 54321
        assert_equal T.must(account).login, "evil@evil.io"
        assert_equal 2, T.must(account).emails.size
      end

      test "handles users without login or email information" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "github.localhost"
            },
            "users": [
              {
                "user_id": 54321,
                "emails": [
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)
        @importer.synchronize_user_accounts_data!
        assert_predicate Failbot.reports, :empty?

        account = T.must(EnterpriseInstallation.where(owner: @business).last).user_accounts.first
        assert_equal T.must(account).remote_user_id, 54321
        assert_equal T.must(account).login, "user-54321"
        assert_equal 0, T.must(account).emails.size
      end

      test "handles users without login or primary email" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "github.localhost"
            },
            "users": [
              {
                "user_id": 54321,
                "emails": [
                  {
                    "email": "not-primary-evil@evil.io"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)
        @importer.synchronize_user_accounts_data!
        account = T.must(EnterpriseInstallation.where(owner: @business).last).user_accounts.first
        assert_equal T.must(account).remote_user_id, 54321
        assert_equal T.must(account).login, "not-primary-evil@evil.io"
        assert_equal 1, T.must(account).emails.size
      end

      test "associates an existing BusinessUserAccounts for cloud users with a matching verified email" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        octocat = create(:user, email: "octocat@github.com")
        octocat.primary_user_email.verify!
        @org.add_member(octocat)
        @business.add_user_accounts([octocat.id])

        user_account = BusinessUserAccount.find_by(business: @business, user: octocat)
        assert user_account

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "BusinessUserAccount.count", 1 do
            @importer.synchronize_user_accounts_data!
          end
        end

        # verify the business user account for octocat was associated with the
        # EnterpriseInstallationUserAccount created for the person's server account
        assert T.must(user_account).reload.enterprise_installation_user_accounts
                                  .joins(:emails)
                                  .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                  .exists?
      end

      test "defaults enterprise account login to account hash login" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        ghec_octocat = create(:user, email: "octocat@github.com", login: "GHEC-Octocat")
        ghec_octocat.primary_user_email.verify!
        @org.add_member(ghec_octocat)
        @business.add_user_accounts([ghec_octocat.id])

        @importer.synchronize_user_accounts_data!

        user_account = BusinessUserAccount.find_by(business: @business, user: ghec_octocat)
        ei_account = T.must(user_account).enterprise_installation_user_accounts.first
        assert_equal T.must(ei_account).login, "octocat"
        refute_equal T.must(ei_account).login, ghec_octocat.login
      end

      test "saves the advanced security status" do
        Failbot.stubs(:report).never
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": #{@business_installation.host_name.to_json}
            },
            "users": [
              {
                "user_id": 12345,
                "using_advanced_security": true,
                "emails": [
                  {
                    "email": "octocat@github.com",
                    "primary": true
                  },
                  {
                    "email": "another@example.com"
                  }
                ]
              },
              {
                "user_id": 54321,
                "using_advanced_security": null,
                "emails": [
                  {
                    "email": "evil@evil.io"
                  },
                  {
                    "email": "not-primary-evil@evil.io"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)

        @importer.synchronize_user_accounts_data!

        account = EnterpriseInstallationUserAccount.joins(:emails).where(enterprise_installation_user_account_emails: { email: "octocat@github.com" }).first
        refute_nil account
        assert T.must(account).using_advanced_security

        account = EnterpriseInstallationUserAccount.joins(:emails).where(enterprise_installation_user_account_emails: { email: "evil@evil.io" }).first
        refute_nil account
        refute T.must(account).using_advanced_security
      end

      test "defaults enterprise account login to dotcom login when account hash missing login" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "github.localhost"
            },
            "users": [
              {
                "user_id": 54321,
                "emails": [
                  {
                    "email": "octocat@github.com",
                    "primary": true
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)

        ghec_octocat = create(:user, email: "octocat@github.com", login: "GHEC-Octocat")
        ghec_octocat.primary_user_email.verify!
        @org.add_member(ghec_octocat)
        @business.add_user_accounts([ghec_octocat.id])

        @importer.synchronize_user_accounts_data!

        user_account = BusinessUserAccount.find_by(business: @business, user: ghec_octocat)
        ei_account = T.must(user_account).enterprise_installation_user_accounts.first

        assert_equal T.must(ei_account).login, ghec_octocat.login
      end

      test "associates an existing BusinessUserAccount for EMU cloud user with a matching profile email" do
        # EMU user setup
        emu_user = create :emu, :owner, email: "octocat@github.com"
        business = emu_user.enterprise_managed_business

        user_account = emu_user.business_user_accounts.find_by(business_id: business.id)
        assert user_account

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "BusinessUserAccount.count", 1 do
            upload = create :enterprise_installation_user_accounts_upload, business: business
            importer = create_importer business: business, installation: nil, upload_id: upload.id
            importer.synchronize_user_accounts_data!
          end
        end

        # verify the business user account for octocat was associated with the
        # EnterpriseInstallationUserAccount created for the person's server account
        assert T.must(user_account).reload.enterprise_installation_user_accounts
                                  .joins(:emails)
                                  .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                  .exists?
      end

      context "Business-level SSO" do
        test "associates an existing BusinessUserAccount for SAML SSO GHEC user with a matching email" do
          accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
          business = create(:business)
          octocat = create(:user, email: "octocat@example.com")
          octocat.primary_user_email.verify!
          business.add_user_accounts([octocat.id])
          provider = create :business_saml_provider, business: business

          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "emails", "value" => "octocat@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: octocat, saml_user_data: saml_user_data)

          user_account = BusinessUserAccount.find_by(business: business, user: octocat)
          assert user_account

          assert_difference "EnterpriseInstallationUserAccount.count", 2 do
            assert_difference "BusinessUserAccount.count", 1 do
              upload = create :enterprise_installation_user_accounts_upload, business: business
              importer = create_importer business: business, installation: nil, upload_id: upload.id
              importer.synchronize_user_accounts_data!
            end
          end

          # verify the business user account for octocat was associated with the
          # EnterpriseInstallationUserAccount created for the person's server account
          assert T.must(user_account).reload.enterprise_installation_user_accounts
                                    .joins(:emails)
                                    .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                    .exists?
        end

        test "does not associate an existing BusinessUserAccount for SAML SSO GHEC user without a matching email" do
          accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
          business = create(:business)
          octocat = create(:user, email: "octocat@example.com")
          octocat.primary_user_email.verify!
          business.add_user_accounts([octocat.id])
          provider = create :business_saml_provider, business: business

          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "NameID", "value" => "octocat" },
          ])
          ext_id = create(:external_identity, provider: business.saml_provider, user: octocat, saml_user_data: saml_user_data)

          user_account = BusinessUserAccount.find_by(business: business, user: octocat)
          assert user_account

          assert_difference "EnterpriseInstallationUserAccount.count", 2 do
            assert_difference "BusinessUserAccount.count", 2 do
              upload = create :enterprise_installation_user_accounts_upload, business: business
              importer = create_importer business: business, installation: nil, upload_id: upload.id
              importer.synchronize_user_accounts_data!
            end
          end

          # verify the business user account for octocat was *not* associated with the
          # EnterpriseInstallationUserAccount created for the person's server account
          refute T.must(user_account).reload.enterprise_installation_user_accounts
                                    .joins(:emails)
                                    .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                    .exists?
        end

        test "associates an existing BusinessUserAccount for SCIM SSO GHEC user with a matching email" do
          accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
          business = create(:business)
          octocat = create(:user, email: "octocat@example.com")
          octocat.primary_user_email.verify!
          business.add_user_accounts([octocat.id])
          provider = create :business_saml_provider, business: business

          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "Octocat-IdP-Id" },
            { "name" => "emails", "value" => "octocat@github.com" },
          ])
          create(:external_identity, provider: business.saml_provider, user: octocat, scim_user_data: scim_user_data)

          user_account = BusinessUserAccount.find_by(business: business, user: octocat)
          assert user_account

          assert_difference "EnterpriseInstallationUserAccount.count", 2 do
            assert_difference "BusinessUserAccount.count", 1 do
              upload = create :enterprise_installation_user_accounts_upload, business: business
              importer = create_importer business: business, installation: nil, upload_id: upload.id
              importer.synchronize_user_accounts_data!
            end
          end

          # verify the business user account for octocat was associated with the
          # EnterpriseInstallationUserAccount created for the person's server account
          assert T.must(user_account).reload.enterprise_installation_user_accounts
                                    .joins(:emails)
                                    .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                    .exists?
        end

        test "does not associate an existing BusinessUserAccount for SCIM SSO GHEC user without a matching email" do
          accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
          business = create(:business)
          octocat = create(:user, email: "octocat@example.com")
          octocat.primary_user_email.verify!
          business.add_user_accounts([octocat.id])
          provider = create :business_saml_provider, business: business

          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "Octocat-IdP-Id" },
            { "name" => "userName", "value" => "octocat" },
          ])
          create(:external_identity, provider: business.saml_provider, user: octocat, scim_user_data: scim_user_data)

          user_account = BusinessUserAccount.find_by(business: business, user: octocat)
          assert user_account

          assert_difference "EnterpriseInstallationUserAccount.count", 2 do
            assert_difference "BusinessUserAccount.count", 2 do
              upload = create :enterprise_installation_user_accounts_upload, business: business
              importer = create_importer business: business, installation: nil, upload_id: upload.id
              importer.synchronize_user_accounts_data!
            end
          end

          # verify the business user account for octocat was *not* associated with the
          # EnterpriseInstallationUserAccount created for the person's server account
          refute T.must(user_account).reload.enterprise_installation_user_accounts
                                    .joins(:emails)
                                    .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                    .exists?
        end

        test "associates an existing BusinessUserAccount for OIDC EMU user with a matching email" do
          accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
          business = create(:business, :enterprise_managed)
          provider = create(:business_oidc_provider, business: business)
          octocat = create(:emu, email: "octocat@example.com")
          octocat.primary_user_email.verify!
          business.add_user_accounts([octocat.id])

          scim_user_data = Platform::Provisioning::ScimUserData.new([
            { "name" => "externalId", "value" => "Octocat-IdP-Id" },
            { "name" => "emails", "value" => "octocat@github.com" },
          ])
          create(:external_identity, provider: business.oidc_provider, user: octocat, scim_user_data: scim_user_data)

          user_account = BusinessUserAccount.find_by(business: business, user: octocat)
          assert user_account

          assert_difference "EnterpriseInstallationUserAccount.count", 2 do
            assert_difference "BusinessUserAccount.count", 1 do
              upload = create :enterprise_installation_user_accounts_upload, business: business
              importer = create_importer business: business, installation: nil, upload_id: upload.id
              importer.synchronize_user_accounts_data!
            end
          end

          # verify the business user account for octocat was associated with the
          # EnterpriseInstallationUserAccount created for the person's server account
          assert T.must(user_account).reload.enterprise_installation_user_accounts
                                    .joins(:emails)
                                    .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                    .exists?
        end
      end

      context "Business Org-level SSO" do
        test "associates an existing BusinessUserAccount for SAML SSO GHEC user with a matching email" do
          accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
          org = create(:organization, billing_type: "invoice", plan: "business_plus")
          business = create(:business, organizations: [org])
          octocat = create(:user, email: "octocat@example.com")
          octocat.primary_user_email.verify!
          org.add_member(octocat)
          business.add_user_accounts([octocat.id])
          provider = create :organization_saml_provider, organization: org
          saml_user_data = Platform::Provisioning::SamlUserData.new([
            { "name" => "emails", "value" => "octocat@github.com" },
          ])
          create(:external_identity, provider: provider, user: octocat, saml_user_data: saml_user_data)

          user_account = BusinessUserAccount.find_by(business: business, user: octocat)
          assert user_account

          assert_difference "EnterpriseInstallationUserAccount.count", 2 do
            assert_difference "BusinessUserAccount.count", 1 do
              upload = create :enterprise_installation_user_accounts_upload, business: business
              importer = create_importer business: business, installation: nil, upload_id: upload.id
              importer.synchronize_user_accounts_data!
            end
          end

          # verify the business user account for octocat was associated with the
          # EnterpriseInstallationUserAccount created for the person's server account
          assert T.must(user_account).reload.enterprise_installation_user_accounts
                                    .joins(:emails)
                                    .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                    .exists?
        end
      end

      test "does not associate an existing BusinessUserAccounts for cloud users without a matching verified email" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        octocat = create(:user, email: "octocat@github.com")
        @org.add_member(octocat)
        @business.add_user_accounts([octocat.id])

        account = BusinessUserAccount.find_by(business: @business, user: octocat)
        assert account

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "BusinessUserAccount.count", 2 do
            @importer.synchronize_user_accounts_data!
          end
        end

        # verify the business user account for octocat was *not* associated with the
        # EnterpriseInstallationUserAccount created for the person's server account
        refute T.must(account).reload.enterprise_installation_user_accounts
                             .joins(:emails)
                             .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                             .exists?
      end

      test "associates existing BusinessUserAccounts for server users" do
        user_account = create :business_user_account, business: @business, user: nil
        other_installation = create(:enterprise_installation, owner: @business)
        other_installation_user = create(:enterprise_installation_user_account,
                                         enterprise_installation: other_installation,
                                         business_user_account: user_account)

        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: other_installation_user,
          email: "octocat@github.com"

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "BusinessUserAccount.count", 1 do
            @importer.synchronize_user_accounts_data!
          end
        end

        # verify the pre-existing business user account is associated to a
        # new enterprise installation user account matched on octocat@github.com
        assert user_account.reload.enterprise_installation_user_accounts
                                  .joins(:emails)
                                  .where(enterprise_installation_user_account_emails: { primary: true, email: "octocat@github.com" })
                                  .where.not(id: other_installation_user.id)
                                  .exists?
      end

      test "associates an existing BusinessUserAccount with a case mismatched email" do
        email = "OCTOCAT@GITHUB.COM"
        octocat = create(:user, email: email)
        octocat.primary_user_email.verify!
        @org.add_member(octocat)
        @business.add_user_accounts([octocat.id])

        user_account = BusinessUserAccount.find_by(business: @business, user: octocat)
        assert user_account

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "BusinessUserAccount.count", 1 do
            @importer.synchronize_user_accounts_data!
          end
        end

        # Verify the pre-existing BusinessUserAccount is associated with a
        # new EnterpriseInstallationUserAccount matched on OCTOCAT@GITHUB.COM
        installation_user = EnterpriseInstallationUserAccount.joins(:emails)
          .where(enterprise_installation_user_account_emails: { primary: true, email: email })
          .first
        assert installation_user&.business_user_account
        assert_equal user_account, T.must(installation_user).business_user_account
      end

      test "does not associate an existing BusinessUserAccounts using non-primary emails" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        octocat = create(:user, email: "another@example.com")
        octocat.primary_user_email.verify!
        @org.add_member(octocat)
        @business.add_user_accounts([octocat.id])

        user_account = BusinessUserAccount.find_by(business: @business, user: octocat)
        assert user_account

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "BusinessUserAccount.count", 2 do
            @importer.synchronize_user_accounts_data!
          end
        end

        # verify that an enterprise installation user was created with a
        # new business user account
        installation_user = EnterpriseInstallationUserAccount.joins(:emails)
                                                             .where(enterprise_installation_user_account_emails: { primary: false, email: "another@example.com" })
                                                             .first
        assert installation_user&.business_user_account
        refute_equal user_account, T.must(installation_user).business_user_account
      end

      test "does not associate an existing BusinessUserAccount using previous primary email matching a GHEC account" do
        # Consider a scenario where we have a GHEC account with a dotcom user with a given primary
        # email address that matches the primary email address used in a GHES installation connected
        # to their GHEC account and a license sync happens. The primary email address of the user on
        # the GHES installation then changes and another license sync is done.
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        octocat = create(:user, email: "octocat@github.com")
        octocat.primary_user_email.verify!
        @org.add_member(octocat)
        @business.add_user_accounts([octocat.id])
        @importer.synchronize_user_accounts_data!

        user_account = BusinessUserAccount.find_by(business: @business, user: octocat)
        assert user_account

        accounts_data = Rails.root.join(
          "test/fixtures/enterprise_installations/other_user_accounts_export_v2.json"
        ).read
        EnterpriseInstallationUserAccountsUpload.any_instance.stubs(:download_and_read_file).returns(accounts_data)
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data accounts_data

        assert_difference "EnterpriseInstallationUserAccount.count", 0 do
          assert_difference "BusinessUserAccount.count", 1 do
            @importer.synchronize_user_accounts_data!
          end
        end

        # Verify that an enterprise installation user with a new BusinessUserAccount is created
        installation_user = EnterpriseInstallationUserAccount.
          joins(:emails).
          where(enterprise_installation_user_account_emails: {
            primary: true, email: "another@example.com"
          }
        ).first

        assert installation_user&.business_user_account
        refute_equal user_account, T.must(installation_user).business_user_account
      end

      test "creates a new BusinessUserAccount for any unmatched uploaded server users" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        octocat = create(:user, email: "octocat@github.com")
        octocat.primary_user_email.verify!
        @org.add_member(octocat)
        @business.add_user_accounts([octocat.id])

        # verify the business user account we're looking for later
        # doesn't already exist
        refute BusinessUserAccount.joins(:enterprise_installation_user_accounts)
                                  .where(enterprise_installation_user_accounts: { login: "eviljdennes" })
                                  .exists?

        assert_difference "EnterpriseInstallationUserAccount.count", 2 do
          assert_difference "BusinessUserAccount.count", 1 do
            @importer.synchronize_user_accounts_data!
          end
        end

        # verify a new business user account was created for eviljdennes
        account = BusinessUserAccount.joins(:enterprise_installation_user_accounts)
                                     .find_by(enterprise_installation_user_accounts: { login: "eviljdennes" })
        assert account
        # the server user's primary email address is set as the user account login
        assert_equal "evil@evil.io", T.must(account).login

      end

      test "updates existing EnterpriseInstallationUserAccounts included in JSON" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        # Create existing EnterpriseInstallationUserAccount records for each
        # entry in the hash, based on the remote_user_id field.
        accounts_hash[:users].each do |user|
          create :enterprise_installation_user_account, \
            enterprise_installation: @business_installation, remote_user_id: user[:user_id]
        end

        @importer.synchronize_user_accounts_data!
        assert_equal accounts_hash[:users].size, @business_installation.user_accounts.size

        first = @business_installation.user_accounts.find_by \
          remote_user_id: accounts_hash[:users][0][:user_id]
        assert_account_synced_from_hash(accounts_hash[:users][0], first)
        second = @business_installation.user_accounts.find_by \
          remote_user_id: accounts_hash[:users][1][:user_id]
        assert_account_synced_from_hash(accounts_hash[:users][1], second)
      end

      test "updates BusinessUserAccount login if primary email has changed" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "#{@business_installation.host_name}"
            },
            "users": [
              {
                "user_id": 12345,
                "emails": [
                  {
                    "email": "octocat@github.com",
                    "primary": true
                  },
                  {
                    "email": "another@example.com"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)

        old_email = "another@example.com"
        user_account = create :business_user_account, business: @business, user: nil, login: old_email
        installation_user = create :enterprise_installation_user_account,
          enterprise_installation: @business_installation, remote_user_id: 12345,
          business_user_account: user_account
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: old_email, primary: true
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "octocat@github.com", primary: false

        @importer.synchronize_user_accounts_data!

        account = T.must(EnterpriseInstallation.where(owner: @business).last).user_accounts.first
        assert_equal T.must(account).remote_user_id, 12345
        assert_equal T.must(account).login, "octocat@github.com"
        assert_equal 2, T.must(account).emails.size
        assert T.must(account).emails.find_by(email: "octocat@github.com").primary?
      end

      test "does not update BusinessUser login if user matched to dotcom user" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        octocat = create(:user, email: "octocat@github.com")
        octocat.primary_user_email.verify!
        @org.add_member(octocat)
        @business.add_user_accounts([octocat.id])

        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "#{@business_installation.host_name}"
            },
            "users": [
              {
                "user_id": 12345,
                "emails": [
                  {
                    "email": "octocat@github.com",
                    "primary": true
                  },
                  {
                    "email": "another@example.com"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)

        @importer.synchronize_user_accounts_data!
        account = T.must(EnterpriseInstallation.where(owner: @business).last).user_accounts.first
        refute_equal T.must(account).login, "octocat@github.com"
      end

      test "don't update BusinessUserAccount login if user associated with multiple instances with different primary email addresses" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "#{@business_installation.host_name}"
            },
            "users": [
              {
                "user_id": 12345,
                "emails": [
                  {
                    "email": "octocat@github.com",
                    "primary": true
                  },
                  {
                    "email": "another@example.com"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)

        user_account = create :business_user_account, business: @business, user: nil, login: "octocat@github.com"

        # First GHES installation user account
        installation_user = create :enterprise_installation_user_account,
          enterprise_installation: @business_installation, remote_user_id: 12345,
          business_user_account: user_account
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "octocat@github.com", primary: true
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "another@example.com", primary: false

        # Second GHES installation user account
        second_business_installation = create(:enterprise_installation, owner: @business, host_name: "github-the-second.example.com")
        installation_user = create :enterprise_installation_user_account,
          enterprise_installation: second_business_installation, remote_user_id: 54321,
          business_user_account: user_account
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "mona@github.com", primary: true
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "octocat@github.com", primary: false

        # Sync from first GHES instance
        @importer.synchronize_user_accounts_data!

        # Perform a sync from a second instance with a different primary email address
        second_data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "#{second_business_installation.host_name}"
            },
            "users": [
              {
                "user_id": 54321,
                "emails": [
                  {
                    "email": "mona@github.com",
                    "primary": true
                  },
                  {
                    "email": "octocat@github.com"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(second_data)

        upload = create :enterprise_installation_user_accounts_upload, business: @business
        second_importer = create_importer installation: second_business_installation, upload_id: upload.id
        second_importer.synchronize_user_accounts_data!

        # Ensure the login hasn't changed
        account = T.must(EnterpriseInstallation.where(owner: @business).last).user_accounts.first
        assert_equal T.must(account).login, "octocat@github.com"
        assert T.must(account).emails.find_by(email: "mona@github.com").primary?
      end

      test "updates BusinessUser login if same on all instances" do
        data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "#{@business_installation.host_name}"
            },
            "users": [
              {
                "user_id": 12345,
                "emails": [
                  {
                    "email": "octocat@github.com",
                    "primary": true
                  },
                  {
                    "email": "another@example.com"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(data)

        user_account = create :business_user_account, business: @business, user: nil, login: "another@example.com"

        # First GHES installation user account
        installation_user = create :enterprise_installation_user_account,
          enterprise_installation: @business_installation, remote_user_id: 12345,
          business_user_account: user_account
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "another@example.com", primary: true
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "octocat@github.com", primary: false

        # Second GHES installation user account
        second_business_installation = create(:enterprise_installation, owner: @business, host_name: "github-the-second.example.com")
        installation_user = create :enterprise_installation_user_account,
          enterprise_installation: second_business_installation, remote_user_id: 54321,
          business_user_account: user_account
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "mona@github.com", primary: true
        create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: installation_user,
          email: "octocat@github.com", primary: false

        # Sync from first GHES instance - this will change the first instance primary email to octocat@github.com but not change the login
        @importer.synchronize_user_accounts_data!
        account = T.must(EnterpriseInstallation.where(owner: @business).first).user_accounts.first
        assert_equal T.must(account).login, "another@example.com"
        assert T.must(account).emails.find_by(email: "octocat@github.com").primary?

        # Perform a sync from a second instance with a matching primary email address
        second_data = <<~JSON
          {
            "version": 1,
            "instance": {
              "hostname": "#{second_business_installation.host_name}"
            },
            "users": [
              {
                "user_id": 54321,
                "emails": [
                  {
                    "email": "octocat@github.com",
                    "primary": true
                  },
                  {
                    "email": "mona@github.com"
                  }
                ]
              }
            ]
          }
        JSON
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(second_data)

        upload = create :enterprise_installation_user_accounts_upload, business: @business
        second_importer = create_importer installation: second_business_installation, upload_id: upload.id
        second_importer.synchronize_user_accounts_data!

        # Ensure the login hasn't changed
        account = T.must(EnterpriseInstallation.where(owner: @business).last).user_accounts.first
        assert_equal T.must(account).login, "another@example.com"
        assert T.must(account).emails.find_by(email: "octocat@github.com").primary?

        # Run again to mimic a third sync which will then update the login to match the primary email used on all GHES instances
        second_importer.synchronize_user_accounts_data!
        account = T.must(EnterpriseInstallation.where(owner: @business).last).user_accounts.first
        assert_equal T.must(account).login, "octocat@github.com"
      end

      test "removes emails associated with the remote user not included in JSON" do
        # Consider the scenario where a user sets their primary email address, a license sync occurs, the user
        # then changes their primary email address by adding a new email and removing the old one, and then license
        # sync occurs again. We don't want to have a situation where the user has two primary email addresses
        # associated with that GHES instance.
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        # Create existing EnterpriseInstallationUserAccount records for each
        # entry in the hash, based on the remote_user_id field and set a primary email for each.
        accounts_hash[:users].each do |user|
          account = create :enterprise_installation_user_account,
            enterprise_installation: @business_installation, remote_user_id: user[:user_id]
          create :enterprise_installation_user_account_email,
            enterprise_installation_user_account: account,
            email: "i-am-not-in-json-#{user[:login]}@github.com", primary: true
        end

        @importer.synchronize_user_accounts_data!
        assert_equal accounts_hash[:users].size, @business_installation.user_accounts.size

        first = @business_installation.user_accounts.find_by \
          remote_user_id: accounts_hash[:users][0][:user_id]
        assert_account_synced_from_hash(accounts_hash[:users][0], first)
        second = @business_installation.user_accounts.find_by \
          remote_user_id: accounts_hash[:users][1][:user_id]
        assert_account_synced_from_hash(accounts_hash[:users][1], second)
      end

      test "destroys user accounts not included in JSON" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        to_get_deleted_business_user_account_one = create :business_user_account, business: @business, user: nil
        to_get_deleted_one = create :enterprise_installation_user_account,
          login: "i-am-not-in-json", enterprise_installation: @business_installation,
          business_user_account: create(:business_user_account, business: @business, user: nil)
        to_get_deleted_one_email = create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: to_get_deleted_one,
          email: "i-am-not-in-json@github.com", primary: true
        to_get_deleted_business_user_account_two = create :business_user_account, business: @business, user: nil
        to_get_deleted_two = create :enterprise_installation_user_account,
          login: "also-am-not-in-json", enterprise_installation: @business_installation,
          business_user_account: to_get_deleted_business_user_account_two
        to_get_deleted_two_email = create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: to_get_deleted_two,
          email: "also-am-not-in-json@github.com", primary: true

        to_get_deleted_one_user = create(:user, :verified, email: to_get_deleted_one_email.email)

        @importer.synchronize_user_accounts_data!

        assert_nil EnterpriseInstallationUserAccount.find_by login: "i-am-not-in-json"
        assert_nil EnterpriseInstallationUserAccountEmail.find_by email: "i-am-not-in-json@github.com"
        assert_nil EnterpriseInstallationUserAccount.find_by login: "also-am-not-in-json"
        assert_nil EnterpriseInstallationUserAccountEmail.find_by email: "also-am-not-in-json@github.com"

        assert_nil BusinessUserAccount.find_by(id: to_get_deleted_business_user_account_one.id)
        assert_nil BusinessUserAccount.find_by(id: to_get_deleted_business_user_account_two.id)

        assert_equal accounts_hash[:users].size, @business_installation.user_accounts.size
      end

      test "destroys user accounts not included in JSON when we look up an existing installation by server_id" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        server_id = accounts_hash[:instance][:server_id]
        installation = create :enterprise_installation, owner: @business, server_id: server_id

        to_get_deleted_business_user_account_one = create :business_user_account, business: @business, user: nil
        to_get_deleted_one = create :enterprise_installation_user_account,
          login: "i-am-not-in-json", enterprise_installation: installation,
          business_user_account: create(:business_user_account, business: @business, user: nil)
        to_get_deleted_one_email = create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: to_get_deleted_one,
          email: "i-am-not-in-json@github.com", primary: true
        to_get_deleted_business_user_account_two = create :business_user_account, business: @business, user: nil
        to_get_deleted_two = create :enterprise_installation_user_account,
          login: "also-am-not-in-json", enterprise_installation: installation,
          business_user_account: to_get_deleted_business_user_account_two
        to_get_deleted_two_email = create :enterprise_installation_user_account_email,
          enterprise_installation_user_account: to_get_deleted_two,
          email: "also-am-not-in-json@github.com", primary: true

        to_get_deleted_one_user = create(:user, :verified, email: to_get_deleted_one_email.email)

        # Do not pass the importer an installation, let it find the installation
        # based on the server_id included in the accounts_hash
        importer = create_importer installation: nil
        importer.synchronize_user_accounts_data!

        assert_nil EnterpriseInstallationUserAccount.find_by login: "i-am-not-in-json"
        assert_nil EnterpriseInstallationUserAccountEmail.find_by email: "i-am-not-in-json@github.com"
        assert_nil EnterpriseInstallationUserAccount.find_by login: "also-am-not-in-json"
        assert_nil EnterpriseInstallationUserAccountEmail.find_by email: "also-am-not-in-json@github.com"

        assert_nil BusinessUserAccount.find_by(id: to_get_deleted_business_user_account_one.id)
        assert_nil BusinessUserAccount.find_by(id: to_get_deleted_business_user_account_two.id)

        assert_equal accounts_hash[:users].size, installation.user_accounts.size
      end

      test "cleans orphaned BusinessUserAccounts after reconciliation" do
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data

        # Create existing EnterpriseInstallationUserAccount records for each
        # entry in the hash, based on the remote_user_id field.
        # Set business_user_account to a record that will be orphaned and
        # deleted after the user account sync
        user_accounts = (1..accounts_hash[:users].size).map do
          create :business_user_account, business: @business, user: nil
        end

        accounts_hash[:users].each_with_index do |user, i|
          create :enterprise_installation_user_account, \
            enterprise_installation: @business_installation,
            remote_user_id: user[:user_id],
            business_user_account: user_accounts[i]
        end

        @importer.synchronize_user_accounts_data!

        user_accounts.each do |user_account|
          assert_nil BusinessUserAccount.find_by(id: user_account.id)
        end
      end

      test "sets sync_state to :success on upload when sync succeeds" do
        @importer.synchronize_user_accounts_data!
        assert_predicate @upload.reload, :sync_success?
      end

      test "sends email when when sync succeeds" do
        assert_performed_email(mailer: "BusinessMailer", action: "sync_user_accounts", args: [@admin, true, @upload]) do
          @importer.synchronize_user_accounts_data!
        end
      end

      test "sends email when when sync fails" do
        EnterpriseInstallationUserAccountsImporter.expects(:parse_user_accounts_data).raises(EnterpriseInstallationUserAccountsImporter::InvalidDataError.new)
        assert_performed_email(mailer: "BusinessMailer", action: "sync_user_accounts", args: [@admin, false, @upload]) do
          @importer.synchronize_user_accounts_data!
        end
      end

      test "instruments business.import_license_usage" do
        events = subscribe "business.import_license_usage"
        @importer.synchronize_user_accounts_data!

        expected_payload = {
          actor: @admin.login,
          actor_id: @admin.id,
          business_id: @business.id,
          business: @business.slug,
          name: @business.name,
          enterprise_installation: @business_installation.host_name,
          enterprise_installation_id: @business_installation.id,
        }

        assert event = events.pop, "business.import_license_usage event was expected"
        assert events.empty?
        assert_equal expected_payload, event.payload
      end

      test "publishes a license snapshot event for each user in the uploaded data" do
        perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
          @importer.synchronize_user_accounts_data!
        end

        assert_hydro_messages(count: 2, schema: "github.billing.v0.LicenseSnapshot")
      end

      test "sets sync_state to :failure on upload when sync fails" do
        # Update @accounts_data to simulate invalid data
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        accounts_hash[:users].first[:user_id] = nil
        invalid_data = JSON.generate accounts_hash
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(invalid_data)

        @importer.synchronize_user_accounts_data!
        assert_predicate @upload.reload, :sync_failure?
      end

      test "sets sync_state to :failure on upload when JSON parsing fails" do
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns("THIS IS NOT JSON DATA")

        @importer.synchronize_user_accounts_data!
        assert_predicate @upload.reload, :sync_failure?
      end

      test "rolls back if sync fails" do
        # Update @accounts_data to simulate invalid data
        accounts_hash = EnterpriseInstallationUserAccountsImporter.parse_user_accounts_data @accounts_data
        accounts_hash[:users].first[:user_id] = nil
        invalid_data = JSON.generate accounts_hash
        EnterpriseInstallationUserAccountsUpload.any_instance.
          stubs(:download_and_read_file).returns(invalid_data)

        assert_no_difference "EnterpriseInstallationUserAccount.count" do
          assert_no_difference "EnterpriseInstallationUserAccountEmail.count" do
            @importer.synchronize_user_accounts_data!
          end
        end
        assert_predicate @upload.reload, :sync_failure?
      end

      test "updates license counts with imported users" do
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob, BusinessUserAccountUpdateAttributesJob]) do
          @importer.synchronize_user_accounts_data!
        end

        # The admin + the two GHES users = 3 total users
        assert_equal 3, @business.reload.consumed_enterprise_licenses
      end
    end

    def create_importer(
      business: @business,
      installation: @business_installation,
      upload_id: @upload.id,
      actor: @admin)
      EnterpriseInstallationUserAccountsImporter.new \
        business: business,
        installation: installation,
        upload_id: upload_id,
        actor: actor
    end

    def assert_account_synced_from_hash(hash, account)
      assert_equal hash[:user_id], account.remote_user_id
      assert_equal hash[:login], account.login
      assert_equal hash[:profile_name], account.profile_name
      assert_equal hash[:site_admin], account.site_admin

      hash[:emails].each do |email|
        assert found = account.emails.find_by(email: email[:email])
        if email.has_key?(:primary)
          assert_equal email[:primary], found.primary?
        else
          refute_predicate found, :primary?
        end
      end
      assert account.emails.to_a.count(&:primary?) <= 1, "enterprise installation account has more than 1 primary email"
    end
  end
end
