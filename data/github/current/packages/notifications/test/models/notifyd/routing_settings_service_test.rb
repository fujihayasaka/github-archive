# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NotifydError < StandardError
    include Notifyd::NetworkHelper::APIError
  end

  class RoutingSettingsServiceTest < GitHub::TestCase
    include GitHub::LoggerHelper

    PAS = Notifyd::ParticipatingActivitySettings
    RS = Notifyd::Proto::RoutingSettings
    Subs = Notifyd::Proto::Subscriptions
    WAS = Notifyd::WatcherActivitySettings
    CIS = Notifyd::ContinuousIntegrationSettings

    setup do
      @user = create(:user)

      GitHub.flipper[:notifyd_enable_issue_thread_subscriptions].enable(@user)
      @routing_setting_id = 202

      @get_response = [
        RS::RoutingSetting.new(
          id: @routing_setting_id,
          user_id: @user.id,
          name: "CI Activity",
          topics: [RS::Topic.new(type: "any", value: "any")],
          channels: [RS::Channel.new(name: "EMAIL", enabled: true)],
          custom_fields: [RS::CustomField.new(name: "delivery_group", value: "ci_activity")],
          filters: [
            RS::Filter.new(subject_type: "any", trigger: "any", reason: "ci_activity"),
            RS::Filter.new(subject_type: "any", trigger: "any", reason: "approval_requested"),
          ],
       ),
      ]

      @delete_ci = RS::DeleteRequest.new(id: @routing_setting_id)

      ci_with_email_settings = CIS.new(
        continuous_integration_email: true,
        continuous_integration_failures_only: false
      ).to_routing_setting

      @ci_with_email = RS::Setting.new(
        topics: ci_with_email_settings.topics.to_a,
        channels: ci_with_email_settings.channels.to_a,
        custom_fields: ci_with_email_settings.custom_fields.to_a,
        filters: ci_with_email_settings.filters.to_a,
      )

      ci_without_email_settings = CIS.new(
        continuous_integration_email: false,
        continuous_integration_failures_only: false
      ).to_routing_setting

      @ci_without_email = RS::Setting.new(
        topics: ci_without_email_settings.topics.to_a,
        channels: ci_without_email_settings.channels.to_a,
        custom_fields: ci_without_email_settings.custom_fields.to_a,
        filters: ci_without_email_settings.filters.to_a,
      )

      ci_with_only_failures_settings = CIS.new(
        continuous_integration_email: true,
        continuous_integration_failures_only: true
      ).to_routing_setting

      @ci_with_only_failures = RS::Setting.new(
        topics: ci_with_only_failures_settings.topics.to_a,
        channels: ci_with_only_failures_settings.channels.to_a,
        custom_fields: ci_with_only_failures_settings.custom_fields.to_a,
        filters: ci_with_only_failures_settings.filters.to_a,
      )

      ci_with_only_failures_without_email_settings = CIS.new(
        continuous_integration_email: false,
        continuous_integration_failures_only: true
      ).to_routing_setting

      @ci_with_only_failures_without_email = RS::Setting.new(
        topics: ci_with_only_failures_without_email_settings.topics.to_a,
        channels: ci_with_only_failures_without_email_settings.channels.to_a,
        custom_fields: ci_with_only_failures_without_email_settings.custom_fields.to_a,
        filters: ci_with_only_failures_without_email_settings.filters.to_a,
      )

      watcher_setting_email = WAS.new(enabled_channels: [WAS::CHANNEL_EMAIL]).to_routing_setting
      @watcher_routing_setting_email = RS::Setting.new(
         channels: watcher_setting_email.channels.to_a,
         topics: watcher_setting_email.topics.to_a,
         filters: watcher_setting_email.filters.to_a,
         custom_fields: watcher_setting_email.custom_fields.to_a,
       )

      participant_setting_email = PAS.new(enabled_channels: [PAS::CHANNEL_EMAIL]).to_routing_setting
      @participant_routing_setting_email = RS::Setting.new(
        channels: participant_setting_email.channels.to_a,
        topics: participant_setting_email.topics.to_a,
        filters: participant_setting_email.filters.to_a,
        custom_fields: participant_setting_email.custom_fields.to_a,
      )

      watcher_setting_no_email = WAS.new(enabled_channels: []).to_routing_setting
      @watcher_routing_setting_no_email = RS::Setting.new(
        channels: watcher_setting_no_email.channels.to_a,
        topics: watcher_setting_no_email.topics.to_a,
        filters: watcher_setting_no_email.filters.to_a,
        custom_fields: watcher_setting_no_email.custom_fields.to_a,
      )

      participant_setting_no_email = PAS.new(enabled_channels: []).to_routing_setting
      @participant_routing_setting_no_email = RS::Setting.new(
        channels: participant_setting_no_email.channels.to_a,
        topics: participant_setting_no_email.topics.to_a,
        filters: participant_setting_no_email.filters.to_a,
        custom_fields: participant_setting_no_email.custom_fields.to_a,
      )

      GitHub.stubs(:dynamic_lab?).returns(false)
      GitHub.stubs(:notifyd_production_url).returns("http://random-url.com")
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @notifyd_client_mock = mock("Notifyd::Client")
      Notifyd.stubs(:client).returns(@notifyd_client_mock)

      def settings(continuous_integration_email, continuous_integration_failures_only)
        settings = Newsies::Settings.new(@user.id)
        settings.continuous_integration_email = continuous_integration_email
        settings.continuous_integration_failures_only = continuous_integration_failures_only
        settings
      end
    end

    context ".save_from_newsies for CI on Enterprise", enterprise_only: true do
      test "returns false as it is disabled" do
        refute Notifyd::RoutingSettingsService.save_from_newsies(@user, settings(true, false), sections: %i[ci])
      end
    end

    context ".save_from_newsies for CI", skip_enterprise: true do
      test "saves routing settings for ci activity with email enabled" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: @ci_with_email.custom_fields.to_a, settings: [@ci_with_email]))
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

        assert Notifyd::RoutingSettingsService.save_from_newsies(@user, settings(true, false), sections: %i[ci])
      end

      test "saves routing settings for ci activity without email enabled" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: @ci_without_email.custom_fields.to_a, settings: [@ci_without_email]))
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

        assert Notifyd::RoutingSettingsService.save_from_newsies(@user, settings(false, false), sections: %i[ci])
      end

      test "saves routing settings for ci activity for only failures" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: @ci_with_only_failures.custom_fields.to_a, settings: [@ci_with_only_failures]))
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

        assert Notifyd::RoutingSettingsService.save_from_newsies(@user, settings(true, true), sections: %i[ci])
      end

      test "saves routing settings for ci activity without email enabled for failures only" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(
            user_id: @user.id,
            replace_by_custom_fields: @ci_with_only_failures_without_email.custom_fields.to_a,
            settings: [@ci_with_only_failures_without_email])
          )
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

        assert Notifyd::RoutingSettingsService.save_from_newsies(@user, settings(false, true), sections: %i[ci])
      end

      test "saves routing settings for ci activity replacing existing one" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: @ci_without_email.custom_fields.to_a, settings: [@ci_without_email]))
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

        assert Notifyd::RoutingSettingsService.save_from_newsies(@user, settings(false, false), sections: %i[ci])
      end

      test "returns false if there are no sections" do
        refute Notifyd::RoutingSettingsService.save_from_newsies(@user, settings(false, false))
      end

      context "errors when notifyd is primary" do
        test "throws error if notifyd client raises an error on BatchReplaceRequest" do
          routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
          routing_settings_client_mock.stubs(:batch_replace).raises(Faraday::ConnectionFailed, "Connection Failed")

          @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

          assert_raises Notifyd::NetworkHelper::APIError do
            Notifyd::RoutingSettingsService.save_from_newsies(@user, settings(true, true), sections: %i[ci])
          end
        end
      end
    end

    context "update_handlers", skip_enterprise: true do
      test "does nothing when issue thread subscriptions are disabled for user" do
        GitHub.flipper[:notifyd_enable_issue_thread_subscriptions].disable

        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

        refute Notifyd::RoutingSettingsService.update_handlers(user: @user, settings: Newsies::Settings.new)
      end

      test "logs are emitted when APIError is raised" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)
        Notifyd::RoutingSettingsService.stubs(:save_from_newsies).raises(NotifydError)

        expected_log = {
          "SeverityText" => "ERROR",
          "Body" => "failed to store notification channel preferences to notifyd",
          "code.namespace" => "NotificationsController",
          "code.function" => "update_handlers_in_notifyd",
          "exception.type" => "Notifyd::NotifydError"
        }

        assert_logged(**expected_log) do
          Notifyd::RoutingSettingsService.update_handlers(user: @user, settings: GitHub.newsies.settings(@user).value)
        end
      end

      test "saves participting and watcher settings when email is enabled" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: @participant_routing_setting_email.custom_fields.to_a, settings: [@participant_routing_setting_email]))
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: @watcher_routing_setting_email.custom_fields.to_a, settings: [@watcher_routing_setting_email]))
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

        GitHub.newsies.get_and_update_settings @user do |settings|
          settings.participating_settings << Newsies::EmailHandler.new
          settings.subscribed_settings << Newsies::EmailHandler.new
        end

        assert Notifyd::RoutingSettingsService.update_handlers(user: @user, settings: GitHub.newsies.settings(@user).value)
      end

      test "saves participting and watcher settings when email is disabled" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: @participant_routing_setting_no_email.custom_fields.to_a, settings: [@participant_routing_setting_no_email]))
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: @watcher_routing_setting_no_email.custom_fields.to_a, settings: [@watcher_routing_setting_no_email]))
          .returns(Twirp::ClientResp.new(data: RS::BatchReplaceResponse.new, error: nil))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

        GitHub.newsies.get_and_update_settings @user do |settings|
          settings.participating_settings.delete("email")
          settings.subscribed_settings.delete("email")
        end

        assert Notifyd::RoutingSettingsService.update_handlers(user: @user, settings: GitHub.newsies.settings(@user).value)
      end
    end

    context ".fetch_from_notifyd", skip_enterprise: true do
      context "CI activities" do
        test "fetched routing settings for ci activity" do
          routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
          get_response = RS::GetResponse.new(routing_setting: @get_response)

          routing_settings_client_mock
            .expects(:get)
            .with(
              RS::GetRequest.new(
                user_id: @user.id,
                filter_by_custom_fields: [RS::CustomField.new(name: "delivery_group", value: "ci_activity")]
              )
            )
            .returns(Twirp::ClientResp.new(data: get_response, error: nil))

          @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

          result = Notifyd::RoutingSettingsService.fetch_from_notifyd(@user, sections: %i[ci])
          assert_equal result, get_response
        end

        test "doesn't specify custom fields filter if invalid sections passed" do
          routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
          get_response = RS::GetResponse.new(routing_setting: @get_response)

          routing_settings_client_mock
            .expects(:get)
            .with(
              RS::GetRequest.new(
                user_id: @user.id,
                filter_by_custom_fields: []
              )
            )
            .returns(Twirp::ClientResp.new(data: get_response, error: nil))

          @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)
          result = Notifyd::RoutingSettingsService.fetch_from_notifyd(@user, sections: %i[foobar])

          assert_equal result, get_response
        end

        test "throws error if get returns error if notifyd is the primary" do
          enabled_user = create(:user)
          routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")
          routing_settings_client_mock
            .expects(:get)
            .with(RS::GetRequest.new(user_id: enabled_user.id, filter_by_custom_fields: []))
            .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))

          @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)

          assert_raises Notifyd::NetworkHelper::APIError do
            Notifyd::RoutingSettingsService.fetch_from_notifyd(enabled_user, sections: %i[foobar])
          end
        end

      end
    end

    context ".fetch_from_notifyd on GHES", enterprise_only: true do
      test "returns empty result as it is disabled" do
        result = Notifyd::RoutingSettingsService.fetch_from_notifyd(@user, sections: %i[foobar])

        assert_equal result, RS::GetResponse.new(
          routing_setting: []
        )
      end
    end


    context "convert routing settings to newsies settings" do
      test "converts to continuous_integration_email_enabled if relevant routing setting set" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "ci activites setting",
              channels: [
                RS::Channel.new(name: "EMAIL", enabled: true),
                RS::Channel.new(name: "PUSH", enabled: false)
              ],
              filters: [
                RS::Filter.new(subject_type: "any", reason: "ci_activity"),
                RS::Filter.new(subject_type: "any", reason: "approval_requested"),
              ],
              custom_fields: [
                RS::CustomField.new(name: "delivery_group", value: "ci_activity"),
                RS::CustomField.new(name: "foo", value: "bar")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        assert extracted_newsies_settings.continuous_integration_email_enabled
        refute extracted_newsies_settings.continuous_integration_failures_only_enabled
      end

      test "converts to continuous_integration_email_enabled if relevant routing setting set when channel case is lower" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "ci activites setting",
              channels: [
                RS::Channel.new(name: "email", enabled: true),
                RS::Channel.new(name: "push", enabled: false)
              ],
              filters: [
                RS::Filter.new(subject_type: "any", reason: "ci_activity"),
                RS::Filter.new(subject_type: "any", reason: "approval_requested")
              ],
              custom_fields: [
                RS::CustomField.new(name: "delivery_group", value: "ci_activity"),
                RS::CustomField.new(name: "foo", value: "bar")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        assert extracted_newsies_settings.continuous_integration_email_enabled
        refute extracted_newsies_settings.continuous_integration_failures_only_enabled
      end

      test "converts disabled to continuous_integration_email_enabled if relevant routing setting set" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "ci activites setting",
              channels: [
                RS::Channel.new(name: "EMAIL", enabled: false),
                RS::Channel.new(name: "PUSH", enabled: false)
              ],
              filters: [
                RS::Filter.new(subject_type: "any", reason: "ci_activity"),
                RS::Filter.new(subject_type: "any", reason: "approval_requested"),
              ],
              custom_fields: [
                RS::CustomField.new(name: "delivery_group", value: "ci_activity"),
                RS::CustomField.new(name: "foo", value: "bar")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        refute extracted_newsies_settings.continuous_integration_email_enabled
        refute extracted_newsies_settings.continuous_integration_failures_only_enabled
      end

      test "returns defaults if filters in routing settings were empty" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "ci not relevant setting",
              channels: [
                RS::Channel.new(name: "EMAIL", enabled: true),
                RS::Channel.new(name: "PUSH", enabled: false)
              ],
              filters: [],
              custom_fields: [
                RS::CustomField.new(name: "delivery_group", value: "ci_activity")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        assert extracted_newsies_settings.continuous_integration_email_enabled
        assert extracted_newsies_settings.continuous_integration_failures_only_enabled
      end

      test "sets default if custom fileds in routing settings was set" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "ci not relevant setting",
              channels: [
                RS::Channel.new(name: "EMAIL", enabled: true),
                RS::Channel.new(name: "PUSH", enabled: false)
              ],
              filters: [
                RS::Filter.new(subject_type: "WorkflowRunAppoval", reason: "approval_requested")
              ],
              custom_fields: [
                RS::CustomField.new(name: "foo", value: "bar")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        assert extracted_newsies_settings.continuous_integration_email_enabled
        assert extracted_newsies_settings.continuous_integration_failures_only_enabled
      end

      test "returns default if unrelevant routing setting was set" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "irrelevant setting",
              channels: [
                RS::Channel.new(name: "EMAIL", enabled: true),
                RS::Channel.new(name: "PUSH", enabled: false)
              ],
              filters: [
                RS::Filter.new(subject_type: "Issue", reason: "mention")
              ],
              custom_fields: [
                RS::CustomField.new(name: "label", value: "1")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        assert extracted_newsies_settings.continuous_integration_email_enabled
        assert extracted_newsies_settings.continuous_integration_failures_only_enabled
      end

      test "converts to continuous_integration_failures_only_enabled if relevant routing setting set" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "irrelevant setting",
              channels: [
                RS::Channel.new(name: "EMAIL", enabled: true),
                RS::Channel.new(name: "PUSH", enabled: false)
              ],
              filters: [
                RS::Filter.new(
                  subject_type: "any",
                  reason: "ci_activity",
                  match_rules: [
                    RS::MatchRule.new(match_rule: "eq", attribute: "failed", value: "true")
                  ]
                ),
                RS::Filter.new(
                  subject_type: "any",
                  reason: "approval_requested",
                  match_rules: []
                )
              ],
              custom_fields: [
                RS::CustomField.new(name: "delivery_group", value: "ci_activity")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        assert extracted_newsies_settings.continuous_integration_email_enabled
        assert extracted_newsies_settings.continuous_integration_failures_only_enabled
      end

      test "converts enabled to continuous_integration_failures_only_enabled if relevant routing setting set" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "irrelevant setting",
              channels: [
                RS::Channel.new(name: "EMAIL", enabled: false),
                RS::Channel.new(name: "PUSH", enabled: false)
              ],
              filters: [
                RS::Filter.new(
                  subject_type: "any",
                  reason: "approval_requested",
                  match_rules: []
                ),
                RS::Filter.new(
                  subject_type: "any",
                  reason: "ci_activity",
                  match_rules: [
                    RS::MatchRule.new(match_rule: "eq", attribute: "failed", value: "true")
                  ]
                ),
              ],
              custom_fields: [
                RS::CustomField.new(name: "delivery_group", value: "ci_activity")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        refute extracted_newsies_settings.continuous_integration_email_enabled
        assert extracted_newsies_settings.continuous_integration_failures_only_enabled
      end

      test "doesn't set continuous_integration_failures_only_enabled if not routing setting set" do
        resp = RS::GetResponse.new(
          routing_setting: [
            RS::RoutingSetting.new(
              user_id: 1,
              name: "irrelevant setting",
              channels: [
                RS::Channel.new(name: "EMAIL", enabled: true),
                RS::Channel.new(name: "PUSH", enabled: false)
              ],
              filters: [
                RS::Filter.new(
                  subject_type: "any",
                  reason: "approval_requested",
                  match_rules: []
                ),
                RS::Filter.new(
                  subject_type: "any",
                  reason: "ci_activity",
                  match_rules: [
                    RS::MatchRule.new(match_rule: "eq", attribute: "foobar", value: "true")
                  ]
                )
              ],
              custom_fields: [
                RS::CustomField.new(name: "delivery_group", value: "ci_activity")
              ]
            ),
          ]
        )

        converter = Notifyd::RoutingSettingsService::Converter.new
        extracted_newsies_settings = converter.routing_settings_to_newsies_stuct(resp.routing_setting)

        assert extracted_newsies_settings.continuous_integration_email_enabled
        refute extracted_newsies_settings.continuous_integration_failures_only_enabled
      end
    end

    context ".delete", skip_enterprise: true do
      test "deletes routing settings by custom fields" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        custom_fields = [
          RS::CustomField.new(name: "name1", value: "value1"),
          RS::CustomField.new(name: "name2", value: "value2")
        ]

        get_response = Twirp::ClientResp.new(
          data: RS::GetResponse.new(routing_setting: @get_response),
          error: nil,
        )

        routing_settings_client_mock
          .expects(:get)
          .with(
            RS::GetRequest.new(
              user_id: @user.id,
              filter_by_custom_fields: custom_fields
            )
          )
          .returns(get_response)

        routing_settings_client_mock
          .expects(:batch_create_and_delete)
          .with(
            RS::BatchCreateAndDeleteRequest.new(
              to_create: [],
              to_delete: [@delete_ci],
            )
          )
          .returns(Twirp::ClientResp.new(data: nil, error: nil))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)
        assert Notifyd::RoutingSettingsService.new(@user, false).delete(custom_fields)
      end

      test "throws error if API call returns error and Notifyd is primary" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        custom_fields = [
          RS::CustomField.new(name: "name1", value: "value1"),
          RS::CustomField.new(name: "name2", value: "value2")
        ]

        get_response = Twirp::ClientResp.new(
          data: RS::GetResponse.new(
            routing_setting: @get_response
          ),
          error: nil,
        )

        routing_settings_client_mock
          .expects(:get)
          .with(
            RS::GetRequest.new(
              user_id: @user.id,
              filter_by_custom_fields: custom_fields
            )
          )
          .returns(get_response)

        routing_settings_client_mock
        .expects(:batch_create_and_delete)
        .with(
          RS::BatchCreateAndDeleteRequest.new(
            to_create: [],
            to_delete: [@delete_ci],
          )
        )
        .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))


        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)
        assert_raises Notifyd::NetworkHelper::APIError do
          Notifyd::RoutingSettingsService.new(@user, true).delete(custom_fields)
        end
      end

      test "returns false if API call returns error and Notifyd is not primary" do
        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        custom_fields = [
          RS::CustomField.new(name: "name1", value: "value1"),
          RS::CustomField.new(name: "name2", value: "value2")
        ]

        get_response = Twirp::ClientResp.new(
          data: RS::GetResponse.new(routing_setting: @get_response),
          error: nil,
        )

        routing_settings_client_mock
          .expects(:get)
          .with(
            RS::GetRequest.new(
              user_id: @user.id,
              filter_by_custom_fields: custom_fields
            )
          )
          .returns(get_response)

        routing_settings_client_mock
          .expects(:batch_create_and_delete)
          .with(
            RS::BatchCreateAndDeleteRequest.new(
              to_create: [],
              to_delete: [@delete_ci],
            )
          )
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))


        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)
        refute Notifyd::RoutingSettingsService.new(@user, false).delete(custom_fields)
      end
    end

    context ".save", skip_enterprise: true do
      test "saves routing settings" do

        custom_fields = [
          RS::CustomField.new(name: "category", value: "thread"),
          RS::CustomField.new(name: "thread_type", value: "gist"),
          RS::CustomField.new(name: "thread_id", value: "123"),
          RS::CustomField.new(name: "owner_type", value: "user"),
          RS::CustomField.new(name: "owner_id", value: "456"),
        ]

        routing_setting_params_base = {
          topics: [RS::Topic.new(type: "gist", value: "123")],
          filters: [RS::Filter.new(reason: "comment", subject_type: "any", trigger: "any")],
          channels: [RS::Channel.new(name: "ALL", enabled: false)],
          custom_fields: custom_fields
        }

        routing_setting_params = routing_setting_params_base.merge(user_id: @user.id, name: "ignore")

        routing_settings_create = [
          RS::CreateRequest.new(routing_setting_params.to_options)
        ]

        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        new_setting = RS::Setting.new(routing_setting_params_base.to_options)
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: new_setting.custom_fields.to_a, settings: [new_setting]))
          .returns(Twirp::ClientResp.new(data: nil, error: nil))
        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)
        assert Notifyd::RoutingSettingsService.new(@user, false, ["test_tag:true"]).save([RS::RoutingSetting.new(routing_setting_params.to_options)])
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "test_tag:true"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:BatchReplaceRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:true"
      end

      test "throws error if API call returns error and Notifyd is primary" do
        custom_fields = [
          RS::CustomField.new(name: "category", value: "thread"),
          RS::CustomField.new(name: "thread_type", value: "gist"),
          RS::CustomField.new(name: "thread_id", value: "123"),
          RS::CustomField.new(name: "owner_type", value: "user"),
          RS::CustomField.new(name: "owner_id", value: "456"),
        ]

        routing_setting_params_base = {
          topics: [RS::Topic.new(type: "gist", value: "123")],
          filters: [RS::Filter.new(reason: "comment", subject_type: "any", trigger: "any")],
          channels: [RS::Channel.new(name: "ALL", enabled: false)],
          custom_fields: custom_fields
        }

        routing_setting_params = routing_setting_params_base.merge(user_id: @user.id, name: "ignore")

        routing_settings_create = [
          RS::CreateRequest.new(routing_setting_params.to_options)
        ]

        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        new_setting = RS::Setting.new(routing_setting_params_base.to_options)
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: new_setting.custom_fields.to_a, settings: [new_setting]))
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))

        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)
        assert_raises Notifyd::NetworkHelper::APIError do
          Notifyd::RoutingSettingsService.new(@user, true).save([RS::RoutingSetting.new(routing_setting_params)])
        end
      end

      test "returns false if API call returns error and Notifyd is not primary" do
        custom_fields = [
          RS::CustomField.new(name: "category", value: "thread"),
          RS::CustomField.new(name: "thread_type", value: "gist"),
          RS::CustomField.new(name: "thread_id", value: "123"),
          RS::CustomField.new(name: "owner_type", value: "user"),
          RS::CustomField.new(name: "owner_id", value: "456"),
        ]

        routing_setting_params_base = {
          topics: [RS::Topic.new(type: "gist", value: "123")],
          filters: [RS::Filter.new(reason: "comment", subject_type: "any", trigger: "any")],
          channels: [RS::Channel.new(name: "ALL", enabled: false)],
          custom_fields: custom_fields
        }

        routing_setting_params = routing_setting_params_base.merge(user_id: @user.id, name: "ignore")

        routing_settings_create = [
          RS::CreateRequest.new(routing_setting_params.to_options)
        ]

        routing_settings_client_mock = mock("Notifyd::RoutingSettings::RoutingSettingsClient")

        new_setting = RS::Setting.new(routing_setting_params_base.to_options)
        routing_settings_client_mock
          .expects(:batch_replace)
          .with(RS::BatchReplaceRequest.new(user_id: @user.id, replace_by_custom_fields: new_setting.custom_fields.to_a, settings: [new_setting]))
          .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.unavailable("unavailable")))
        @notifyd_client_mock.stubs(:routing_settings).returns(routing_settings_client_mock)
        refute Notifyd::RoutingSettingsService.new(@user, false, ["test_tag:true"]).save([RS::RoutingSetting.new(routing_setting_params)])
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "test_tag:true"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "request:BatchReplaceRequest"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "success:false"
        assert_includes GitHub.dogstats.increments("notifications.notifyd_request").last.tags, "error:unavailable"
      end
    end
  end
end
