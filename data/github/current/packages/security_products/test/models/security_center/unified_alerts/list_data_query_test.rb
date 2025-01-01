# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    class ListDataQueryTest < GitHub::TestCase
      extend T::Sig
      include ::SecurityOverviewAnalytics::TestFixtures

      ErrorMock = Struct.new(:msg)
      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @user_session = create(:user_session, user: @org_admin)
        @org = create(:organization, business: @biz, admin: @org_admin)
        @repo = create(:private_repository, owner: @org)

        @archived_repo = create(:archived_repository, owner: @org)
        create_repo_alerts(repository: @archived_repo)
      end

      setup do
        SecurityFeatures.stubs(:visible_features).returns([
          SecurityFeatures::SECRET_SCANNING ,
          SecurityFeatures::CODE_SCANNING,
          SecurityFeatures::DEPENDABOT_ALERTS,
        ])
        @query = ::Search::Queries::SecurityCenter::QueryParser.new("is:open archived:false")
      end

      test "raises ArgumentError if cursor value is invalid" do
        create_repo_alerts(repository: @repo)

        assert_raises ArgumentError do
          ListDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run(cursor: "-1")
        end

        assert_raises ArgumentError do
          ListDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run(cursor: "test")
        end
      end

      test "returns list of alerts and sorted by severity -> created_at -> id" do
        create_repo_alerts(repository: @repo)

        # Stubs away hydration function to focus on validating data query logic
        ListDataQuery.any_instance.stubs(:hydrate_alerts_data!)

        result = ListDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run(cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alerts = result.alerts
        assert_equal 10, alerts.count

        assert_equal @repo.id, T.must(alerts[0])[:repository_id]
        assert_equal 6, T.must(alerts[0])[:alert_number]
        assert_equal SecurityFeatures::CODE_SCANNING, T.must(alerts[0])[:feature_type]

        assert_equal @repo.id, T.must(alerts[1])[:repository_id]
        assert_equal 6, T.must(alerts[1])[:alert_number]
        assert_equal SecurityFeatures::DEPENDABOT_ALERTS, T.must(alerts[1])[:feature_type]

        assert_equal @repo.id, T.must(alerts[2])[:repository_id]
        assert_equal 6, T.must(alerts[2])[:alert_number]
        assert_equal SecurityFeatures::SECRET_SCANNING, T.must(alerts[2])[:feature_type]

        assert_equal @repo.id, T.must(alerts[3])[:repository_id]
        assert_equal 7, T.must(alerts[3])[:alert_number]
        assert_equal SecurityFeatures::CODE_SCANNING, T.must(alerts[3])[:feature_type]

        assert_equal @repo.id, T.must(alerts[4])[:repository_id]
        assert_equal 7, T.must(alerts[4])[:alert_number]
        assert_equal SecurityFeatures::DEPENDABOT_ALERTS, T.must(alerts[4])[:feature_type]

        assert_equal @repo.id, T.must(alerts[5])[:repository_id]
        assert_equal 8, T.must(alerts[5])[:alert_number]
        assert_equal SecurityFeatures::CODE_SCANNING, T.must(alerts[5])[:feature_type]

        assert_equal @repo.id, T.must(alerts[6])[:repository_id]
        assert_equal 8, T.must(alerts[6])[:alert_number]
        assert_equal SecurityFeatures::DEPENDABOT_ALERTS, T.must(alerts[6])[:feature_type]

        assert_equal @repo.id, T.must(alerts[7])[:repository_id]
        assert_equal 9, T.must(alerts[7])[:alert_number]
        assert_equal SecurityFeatures::CODE_SCANNING, T.must(alerts[7])[:feature_type]

        assert_equal @repo.id, T.must(alerts[8])[:repository_id]
        assert_equal 9, T.must(alerts[8])[:alert_number]
        assert_equal SecurityFeatures::DEPENDABOT_ALERTS, T.must(alerts[8])[:feature_type]

        assert_equal @repo.id, T.must(alerts[9])[:repository_id]
        assert_equal 10, T.must(alerts[9])[:alert_number]
        assert_equal SecurityFeatures::CODE_SCANNING, T.must(alerts[9])[:feature_type]
      end

      test "returns list of alerts based on security features input" do
        create_repo_alerts(repository: @repo)

        # Stubs away hydration function to focus on validating data query logic
        ListDataQuery.any_instance.stubs(:hydrate_alerts_data!)

        result = ListDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: [SecurityFeatures::SECRET_SCANNING], query: @query)
          .run(cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alerts = result.alerts
        assert_equal 1, alerts.count

        assert_equal @repo.id, T.must(alerts[0])[:repository_id]
        assert_equal 6, T.must(alerts[0])[:alert_number]
        assert_equal SecurityFeatures::SECRET_SCANNING, T.must(alerts[0])[:feature_type]
      end

      test "supports paging and contains next cursor" do
        create_repo_alerts(repository: @repo)

        # Stubs away hydration function to focus on validating data query logic
        ListDataQuery.any_instance.stubs(:hydrate_alerts_data!)

        result = ListDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run(cursor: "1", page_size: 2)
        assert_equal "0", result.previous
        assert_equal "3", result.next

        alerts = result.alerts
        assert_equal 2, alerts.count

        assert_equal @repo.id, T.must(alerts[0])[:repository_id]
        assert_equal 6, T.must(alerts[0])[:alert_number]
        assert_equal SecurityFeatures::DEPENDABOT_ALERTS, T.must(alerts[0])[:feature_type]

        assert_equal @repo.id, T.must(alerts[1])[:repository_id]
        assert_equal 6, T.must(alerts[1])[:alert_number]
        assert_equal SecurityFeatures::SECRET_SCANNING, T.must(alerts[1])[:feature_type]
      end

      test "returns alerts of enabled feature types only" do
        create_repo_alerts(repository: @repo, enabled_features: [SecurityFeatures::SECRET_SCANNING])

        # Stubs away hydration function to focus on validating data query logic
        ListDataQuery.any_instance.stubs(:hydrate_alerts_data!)

        result = ListDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run(cursor: "0")
        assert_nil result.previous
        assert_nil result.next

        alerts = result.alerts
        assert_equal 1, alerts.count

        assert_equal @repo.id, T.must(alerts[0])[:repository_id]
        assert_equal 6, T.must(alerts[0])[:alert_number]
        assert_equal SecurityFeatures::SECRET_SCANNING, T.must(alerts[0])[:feature_type]
      end

      test "returns empty result if no revision data available" do
        create_repo_alerts(repository: @repo, no_alert_data: true)

        # Stubs away hydration function to focus on validating data query logic
        ListDataQuery.any_instance.stubs(:hydrate_alerts_data!)

        result = ListDataQuery
          .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
          .run(cursor: "0")

        assert_nil result.previous
        assert_nil result.next
        assert_equal 0, result.alerts.count
      end

      context "#hydrate_alerts_data!" do
        test "is called by query" do
          create_repo_alerts(repository: @repo)

          ListDataQuery.any_instance.expects(:hydrate_alerts_data!).once

          result = ListDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run(cursor: "0")

          alerts = result.alerts
          assert_equal 10, alerts.count
        end

        test "hydrates repository metadata" do
          create_repo_alerts(repository: @repo)

          # Stubs away hydration functions not being tested
          ListDataQuery.any_instance.expects(:hydrate_dependabot_alerts!).once
          ListDataQuery.any_instance.expects(:hydrate_code_scanning_alerts!).once
          ListDataQuery.any_instance.expects(:hydrate_secret_scanning_alerts!).once

          result = ListDataQuery
            .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
            .run(cursor: "0")

          alerts = result.alerts
          assert_equal 10, alerts.count

          alerts.each do |alert|
            assert_equal @repo.id, alert[:repository_id]
            assert_equal @repo.name, alert[:repository_name]
            assert_equal @repo.permalink, alert[:repository_href]
            assert_equal @repo.visibility, alert[:repository_visibility]
            assert_equal @repo.repo_type_icon, alert[:repository_type_icon]
          end
        end

        context "#hydrate_dependabot_alerts!" do
          test "hydrates dependabot alerts data" do
            create_repo_alerts(repository: @repo, enabled_features: [SecurityFeatures::DEPENDABOT_ALERTS], no_alert_data: true)
            alert_rev = create(:soa_dependabot_alert_revision, date_id: 20240502, repository: @repo, alert_number: 1)
            source_dependabot_alert = create(:repository_vulnerability_alert, repository: @repo, number: alert_rev.alert_number)

            # Stubs away hydration functions not being tested
            ListDataQuery.any_instance.expects(:hydrate_code_scanning_alerts!).once
            ListDataQuery.any_instance.expects(:hydrate_secret_scanning_alerts!).once

            result = ListDataQuery
              .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
              .run(cursor: "0")

            alerts = result.alerts
            assert_equal 1, alerts.count

            dependabot_alert = T.must(alerts[0])
            assert_equal SecurityFeatures::DEPENDABOT_ALERTS, dependabot_alert[:feature_type]
            assert_equal @repo.id, dependabot_alert[:repository_id]
            assert_equal @repo.name, dependabot_alert[:repository_name]
            assert_equal @repo.permalink, dependabot_alert[:repository_href]
            assert_equal @repo.visibility, dependabot_alert[:repository_visibility]
            assert_equal @repo.repo_type_icon, dependabot_alert[:repository_type_icon]
            assert_equal source_dependabot_alert.number, dependabot_alert[:alert_number]
            assert_equal "/#{@repo.owner.display_login}/#{@repo.name}/security/dependabot/#{alert_rev.alert_number}", dependabot_alert[:alert_href]

            # TODO: data fields being hydrated is final and test will be updated as we revisit data contract.
            # Work: https://github.com/github/security-center/issues/5380
            assert_equal source_dependabot_alert.title, dependabot_alert[:alert_title]
            assert_equal source_dependabot_alert.severity, dependabot_alert[:alert_severity]
          end
        end

        context "#hydrate_code_scanning_alerts!" do
          test "hydrates code scanning alerts data" do
            create_repo_alerts(repository: @repo, enabled_features: [SecurityFeatures::CODE_SCANNING], no_alert_data: true)
            alert_rev = create(:soa_code_scanning_alert_revision, date_id: 20240502, repository: @repo, alert_number: 1)

            # Stubs away hydration functions not being tested
            ListDataQuery.any_instance.expects(:hydrate_dependabot_alerts!).once
            ListDataQuery.any_instance.expects(:hydrate_secret_scanning_alerts!).once

            GitHub::Turboscan
              .expects(:alert)
              .with(has_entries(repository_id: alert_rev.repository_id, number: alert_rev.alert_number))
              .once
              .returns(
                Twirp::ClientResp.new(
                  data: Turboscan::Proto::AlertResponse.new({
                    result: Turboscan::Proto::Result.new({
                      number: alert_rev.alert_number,
                      rule: Turboscan::Proto::Rule.new(short_description: "woof_rule"),
                      tool: Turboscan::Proto::ToolDescription.new(name: "barr_tool")
                    })
                  })
                )
              )

            result = ListDataQuery
              .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
              .run(cursor: "0")

            alerts = result.alerts
            assert_equal 1, alerts.count

            code_scanning_alert = T.must(alerts[0])
            assert_equal SecurityFeatures::CODE_SCANNING, code_scanning_alert[:feature_type]
            assert_equal @repo.id, code_scanning_alert[:repository_id]
            assert_equal @repo.name, code_scanning_alert[:repository_name]
            assert_equal @repo.permalink, code_scanning_alert[:repository_href]
            assert_equal @repo.visibility, code_scanning_alert[:repository_visibility]
            assert_equal @repo.repo_type_icon, code_scanning_alert[:repository_type_icon]
            assert_equal alert_rev.alert_number, code_scanning_alert[:alert_number]
            assert_equal "/#{@repo.owner.display_login}/#{@repo.name}/security/code-scanning/#{alert_rev.alert_number}", code_scanning_alert[:alert_href]
            # from hydrate_code_scanning_alerts!
            # TODO: data fields being hydrated is final and test will be updated as we revisit data contract.
            # Work: https://github.com/github/security-center/issues/5380
            assert_equal "woof_rule", code_scanning_alert[:alert_title]
            assert_equal "barr_tool", code_scanning_alert[:alert_tool]
          end

          test "retries on request errors and skips alert if retries were not successful" do
            create_repo_alerts(repository: @repo, enabled_features: [SecurityFeatures::CODE_SCANNING], no_alert_data: true)
            alert_rev = create(:soa_code_scanning_alert_revision, date_id: 20240502, repository: @repo, alert_number: 1)

            # Stubs away hydration functions not being tested
            ListDataQuery.any_instance.expects(:hydrate_dependabot_alerts!).once
            ListDataQuery.any_instance.expects(:hydrate_secret_scanning_alerts!).once

            # Total number of requests = 1 + retries
            GitHub::Turboscan
              .expects(:alert)
              .with(has_entries(repository_id: alert_rev.repository_id, number: alert_rev.alert_number))
              .times(4)
              .returns(
                Twirp::ClientResp.new(error: ErrorMock.new(msg: "oops"))
              )
            Failbot.expects(:report).with("oops. number of retries: 0/3").once
            Failbot.expects(:report).with("oops. number of retries: 1/3").once
            Failbot.expects(:report).with("oops. number of retries: 2/3").once
            Failbot.expects(:report).with("oops. number of retries: 3/3").once

            result = ListDataQuery
              .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
              .run(cursor: "0")

            alerts = result.alerts
            assert_equal 1, alerts.count

            code_scanning_alert = T.must(alerts[0])
            assert_equal SecurityFeatures::CODE_SCANNING, code_scanning_alert[:feature_type]
            assert_equal @repo.id, code_scanning_alert[:repository_id]
            assert_equal alert_rev.alert_number, code_scanning_alert[:alert_number]
            assert_equal SecurityFeatures::CODE_SCANNING, code_scanning_alert[:feature_type]
            assert_equal @repo.id, code_scanning_alert[:repository_id]
            assert_equal @repo.name, code_scanning_alert[:repository_name]
            assert_equal @repo.permalink, code_scanning_alert[:repository_href]
            assert_equal @repo.visibility, code_scanning_alert[:repository_visibility]
            assert_equal @repo.repo_type_icon, code_scanning_alert[:repository_type_icon]
            assert_equal alert_rev.alert_number, code_scanning_alert[:alert_number]
            assert_equal "/#{@repo.owner.display_login}/#{@repo.name}/security/code-scanning/#{alert_rev.alert_number}", code_scanning_alert[:alert_href]
            # No data filled for due to request error
            # TODO: data fields being hydrated is final and test will be updated as we revisit data contract.
            # Work: https://github.com/github/security-center/issues/5380
            assert_nil code_scanning_alert[:alert_title]
            assert_nil code_scanning_alert[:alert_tool]
          end
        end

        context "#hydrate_secret_scanning_alerts!" do
          test "hydrates secret scanning alerts data" do
            create_repo_alerts(repository: @repo, enabled_features: [SecurityFeatures::SECRET_SCANNING], no_alert_data: true)
            alert_rev = create(:soa_secret_scanning_alert_revision, date_id: 20240502, repository: @repo, alert_number: 1)

            # Stubs away hydration functions not being tested
            ListDataQuery.any_instance.expects(:hydrate_dependabot_alerts!).once
            ListDataQuery.any_instance.expects(:hydrate_code_scanning_alerts!).once

            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token)
              .with(has_entries(repository_id: alert_rev.repository_id, token_id: alert_rev.alert_number))
              .once
              .returns(
                Twirp::ClientResp.new(
                  data: GitHub::Proto::SecretScanning::Api::V2::GetTokenResponse.new(
                    token: GitHub::Proto::SecretScanning::Api::V2::Token.new(
                      number: alert_rev.alert_number,
                      label: "barr",
                      encrypted_token: SecretScanning::Encryption::EncryptedSecretsCryptoHelper.encrypt_secret(
                        "woof",
                        encryption_key: GitHub.secret_scanning_encrypted_secrets_delimited_shared_transit_keys.split(";").last
                      ),
                    )
                  )
                )
              )

            result = ListDataQuery
              .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
              .run(cursor: "0")

            alerts = result.alerts
            assert_equal 1, alerts.count

            secret_scanning_alert = T.must(alerts[0])
            assert_equal SecurityFeatures::SECRET_SCANNING, secret_scanning_alert[:feature_type]
            assert_equal @repo.id, secret_scanning_alert[:repository_id]
            assert_equal @repo.name, secret_scanning_alert[:repository_name]
            assert_equal @repo.permalink, secret_scanning_alert[:repository_href]
            assert_equal @repo.visibility, secret_scanning_alert[:repository_visibility]
            assert_equal @repo.repo_type_icon, secret_scanning_alert[:repository_type_icon]
            assert_equal alert_rev.alert_number, secret_scanning_alert[:alert_number]
            assert_equal "/#{@repo.owner.display_login}/#{@repo.name}/security/secret-scanning/#{alert_rev.alert_number}", secret_scanning_alert[:alert_href]
            # from hydrate_code_scanning_alerts!
            # TODO: data fields being hydrated is final and test will be updated as we revisit data contract.
            # Work: https://github.com/github/security-center/issues/5380
            assert_equal "barr", secret_scanning_alert[:alert_title]
            assert_equal "woof", secret_scanning_alert[:alert_raw_secret]
          end

          test "retries on request errors and skips alert if retries were not successful" do
            create_repo_alerts(repository: @repo, enabled_features: [SecurityFeatures::SECRET_SCANNING], no_alert_data: true)
            alert_rev = create(:soa_secret_scanning_alert_revision, date_id: 20240502, repository: @repo, alert_number: 1)

            # Stubs away hydration functions not being tested
            ListDataQuery.any_instance.expects(:hydrate_dependabot_alerts!).once
            ListDataQuery.any_instance.expects(:hydrate_code_scanning_alerts!).once

            # Total number of requests = 1 + retries
            GitHub::TokenScanning::Service::Client.any_instance
              .expects(:get_token)
              .with(has_entries(repository_id: alert_rev.repository_id, token_id: alert_rev.alert_number))
              .times(4)
              .returns(
                Twirp::ClientResp.new(error: ErrorMock.new(msg: "oops"))
              )
            Failbot.expects(:report).with("oops. number of retries: 0/3").once
            Failbot.expects(:report).with("oops. number of retries: 1/3").once
            Failbot.expects(:report).with("oops. number of retries: 2/3").once
            Failbot.expects(:report).with("oops. number of retries: 3/3").once

            result = ListDataQuery
              .for_organization(@org, user: @org_admin, user_session: @user_session, tools: VALID_TOOLS, query: @query)
              .run(cursor: "0")

            alerts = result.alerts
            assert_equal 1, alerts.count

            secret_scanning_alert = T.must(alerts[0])
            assert_equal SecurityFeatures::SECRET_SCANNING, secret_scanning_alert[:feature_type]
            assert_equal @repo.id, secret_scanning_alert[:repository_id]
            assert_equal @repo.name, secret_scanning_alert[:repository_name]
            assert_equal @repo.permalink, secret_scanning_alert[:repository_href]
            assert_equal @repo.visibility, secret_scanning_alert[:repository_visibility]
            assert_equal @repo.repo_type_icon, secret_scanning_alert[:repository_type_icon]
            assert_equal alert_rev.alert_number, secret_scanning_alert[:alert_number]
            assert_equal "/#{@repo.owner.display_login}/#{@repo.name}/security/secret-scanning/#{alert_rev.alert_number}", secret_scanning_alert[:alert_href]
            # No data filled for due to request error
            # TODO: data fields being hydrated is final and test will be updated as we revisit data contract.
            # Work: https://github.com/github/security-center/issues/5380
            assert_nil secret_scanning_alert[:alert_title]
            assert_nil secret_scanning_alert[:alert_raw_secret]
          end
        end
      end
    end
  end
end
