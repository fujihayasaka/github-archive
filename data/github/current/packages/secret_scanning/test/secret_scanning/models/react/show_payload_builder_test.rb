# typed: true
# frozen_string_literal: true

require "test_helper"

class ShowPayloadBuilderTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  LocationInfoMock = Struct.new(:included_locations, :commit_oids, :custom_pattern_data, :has_ignored_locations, :included_locations_count, :related_alerts, :related_public_leaks)
  CommitMock = Struct.new(:author_email, :author_emails)

  fixtures do
    @user = create(:user)
    @user2 = create(:user)
    @org = create(:business_plus_organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @repo_with_validity_checks_ff_off = create(:repository, owner: @org)

    @secret_author = create(:user, login: "nonadmin1")
    create(:user_email, :verified, user: @secret_author, email: "secret_author@github.com")
    create(:collaborator, repository: @repo, collaborator: @secret_author, permission: "write")

    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager = create(:user)
    @security_manager_team.add_member(@security_manager)
    @repo.add_team(@security_manager_team, action: :read)
    @repo_with_validity_checks_ff_off.add_team(@security_manager_team, action: :read)

    @view_secret_scanning_alerts_user = create(:user, name: "view-secret-scanning-alerts-user")
    grant_custom_role(user: @view_secret_scanning_alerts_user, target: @repo, fgps: [:view_secret_scanning_alerts])

    @validity_last_checked = Time.parse("2022-11-21").freeze

    @location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21"), commit_oid: "b5d4f15a4dd41646405f11fb107aa8efb16c98a4").freeze
    @token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2022-10-21"),
      first_location: @location,
      id: 1,
      label: "Adafruit IO Key",
      token_type: "adafruit_io_key",
      repository_id: @repo.id,
      number: 1,
      validity: :TOKEN_VALIDITY_ACTIVE,
      validation_details: {
        validity_last_checked: @validity_last_checked
      }
    ).freeze

    @resolved_token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2022-10-21"),
      first_location: @location,
      id: 1,
      label: "Adafruit IO Key",
      token_type: "adafruit_io_key",
      repository_id: @repo.id,
      number: 1,
      validity: :TOKEN_VALIDITY_ACTIVE,
      validation_details: {
        validity_last_checked: @validity_last_checked
      },
      resolution: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::USED_IN_TESTS,
    ).freeze

    @llm_token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2022-10-21"),
      first_location: @location,
      id: 1,
      label: "password",
      token_type: "Password",
      repository_id: @repo.id,
      number: 1,
      validity: :TOKEN_VALIDITY_ACTIVE,
      validation_details: {
        validity_last_checked: @validity_last_checked
      },
      llm_detected: true
    ).freeze

    @token_from_api_no_validity_check_ff = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2022-10-21"),
      first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
      id: 1,
      label: "Adafruit IO Key",
      token_type: "adafruit_io_key",
      repository_id: @repo_with_validity_checks_ff_off.id,
      number: 1,
      validity: :TOKEN_VALIDITY_ACTIVE,
      validation_details: {
        validity_last_checked: @validity_last_checked
      }
    ).freeze

    @secret_author_location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
      created_at: Time.parse("2022-10-21"),
      commit_oid: "5ece7b537e484831ccc880b4d2338ca05acf33da",
    ).freeze
    @secret_author_token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2022-10-21"),
      first_location: @secret_author_location,
      id: 1,
      label: "Adafruit IO Key",
      token_type: "adafruit_io_key",
      repository_id: @repo.id,
      number: 1,
      validity: :TOKEN_VALIDITY_ACTIVE,
      validation_details: {
        validity_last_checked: @validity_last_checked
      }
    ).freeze
  end

  setup do
    SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:show_page_serialize_location_refactor_enabled?).returns(true)
    @payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(@repo, @user).freeze
    @payload_builder_no_ff = SecretScanning::Models::React::ShowPayloadBuilder.new(@repo_with_validity_checks_ff_off, @user).freeze
    @security_manager_payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(@repo, @security_manager).freeze
  end

  context "show page react payload" do
    test "includes one click reporting enabled flag set to true when enabled" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:one_click_reporting_enabled?).returns(true)
      token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
      actual_payload = @payload_builder.page_payload(token, 1)
      actual_alert = actual_payload[:alert]

      assert_equal SecretScanning::Models::Alert, actual_alert.class
      assert_equal 1, actual_alert.number
      assert_equal "Adafruit IO Key", actual_alert.label
      assert_equal "adafruit_io_key", actual_alert.token_type
      assert_equal :TOKEN_VALIDITY_ACTIVE, actual_alert.validity
      assert_equal @validity_last_checked, actual_alert.validity_last_checked
      assert_equal actual_payload[:repository][:owner_type], "ORGANIZATION"
      assert actual_payload[:one_click_reporting_enabled]
    end

    test "includes one click reporting enabled flag set to false when not enabled" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:one_click_reporting_enabled?).returns(false)
      token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
      actual_payload = @payload_builder.page_payload(token, 1)
      actual_alert = actual_payload[:alert]

      assert_equal SecretScanning::Models::Alert, actual_alert.class
      assert_equal 1, actual_alert.number
      assert_equal "Adafruit IO Key", actual_alert.label
      assert_equal "adafruit_io_key", actual_alert.token_type
      assert_equal :TOKEN_VALIDITY_ACTIVE, actual_alert.validity
      assert_equal @validity_last_checked, actual_alert.validity_last_checked
      assert_equal actual_payload[:repository][:owner_type], "ORGANIZATION"
      refute actual_payload[:one_click_reporting_enabled]
    end

    test "payload from token scan result returns correct data (including validity)" do
      token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
      actual_payload = @payload_builder.page_payload(token, 1)
      actual_alert = actual_payload[:alert]

      assert_equal SecretScanning::Models::Alert, actual_alert.class
      assert_equal 1, actual_alert.number
      assert_equal "Adafruit IO Key", actual_alert.label
      assert_equal "adafruit_io_key", actual_alert.token_type
      assert_equal :TOKEN_VALIDITY_ACTIVE, actual_alert.validity
      assert_equal @validity_last_checked, actual_alert.validity_last_checked
      assert_equal actual_payload[:repository][:owner_type], "ORGANIZATION"
    end

    context "payload from token scan result shows public leak metadata and/or feature flag if enabled" do
      test_cases = [
        { publicly_leaked: true, feature_flag_enabled: true },
        { publicly_leaked: true, feature_flag_enabled: false },
        { publicly_leaked: false, feature_flag_enabled: true },
        { publicly_leaked: false, feature_flag_enabled: false },
      ]
      test_cases.each do |tc|
        publicly_leaked = tc[:publicly_leaked]
        feature_flag_enabled = tc[:feature_flag_enabled]
        tag_expected = tc[:tag_expected]

        test "publicly_leaked: #{publicly_leaked}, feature_flag_enabled: #{feature_flag_enabled}" do
          if feature_flag_enabled
            enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS)
          else
            disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS)
          end

          token = GitHub::TokenScanning::Service::Token.new(GitHub::Proto::SecretScanning::Api::V2::Token.new(
            created_at: Time.parse("2022-10-21"),
            first_location: @location,
            id: 1,
            label: "Adafruit IO Key",
            token_type: "adafruit_io_key",
            repository_id: @repo.id,
            number: 1,
            publicly_leaked: publicly_leaked,
          ), @repo)
          actual_payload = @payload_builder.page_payload(token, 1)
          actual_alert = T.must(actual_payload)[:alert]

          assert_equal publicly_leaked, actual_alert.publicly_leaked
          if feature_flag_enabled
            assert actual_alert.feature_flags[:secret_scanning_show_single_alert_view_metadata_tags], "#{actual_payload.inspect}"
          else
            refute actual_alert.feature_flags[:secret_scanning_show_single_alert_view_metadata_tags], "#{actual_payload.inspect}"
          end
        end
      end
    end

    context "payload from token scan result shows internal leak metadata and/or feature flag if enabled" do
      test_cases = [
        { internally_leaked: true, feature_flag_enabled: true },
        { internally_leaked: true, feature_flag_enabled: false },
        { internally_leaked: false, feature_flag_enabled: true },
        { internally_leaked: false, feature_flag_enabled: false },
      ]
      test_cases.each do |tc|
        internally_leaked = tc[:internally_leaked]
        feature_flag_enabled = tc[:feature_flag_enabled]
        tag_expected = tc[:tag_expected]

        test "internally_leaked: #{internally_leaked}, feature_flag_enabled: #{feature_flag_enabled}" do
          if feature_flag_enabled
            enable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS)
          else
            disable_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::SHOW_SINGLE_ALERT_VIEW_METADATA_TAGS)
          end

          token = GitHub::TokenScanning::Service::Token.new(GitHub::Proto::SecretScanning::Api::V2::Token.new(
            created_at: Time.parse("2022-10-21"),
            first_location: @location,
            id: 1,
            label: "Adafruit IO Key",
            token_type: "adafruit_io_key",
            repository_id: @repo.id,
            number: 1,
            multi_repo: internally_leaked,
          ), @repo)
          actual_payload = @payload_builder.page_payload(token, 1)
          actual_alert = T.must(actual_payload)[:alert]

          assert_equal internally_leaked, actual_alert.multi_repo
          if feature_flag_enabled
            assert actual_alert.feature_flags[:secret_scanning_show_single_alert_view_metadata_tags], "#{actual_payload.inspect}"
          else
            refute actual_alert.feature_flags[:secret_scanning_show_single_alert_view_metadata_tags], "#{actual_payload.inspect}"
          end
        end
      end
    end

    test "generic secret payload includes survey info" do
      SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:show_user_feedback_link?).returns(true)

      token = GitHub::TokenScanning::Service::Token.new(@llm_token_from_api, @repo)
      actual_payload = @payload_builder.page_payload(token, 1)
      actual_alert = actual_payload[:alert]

      assert_equal SecretScanning::Models::Alert, actual_alert.class
      assert_equal 1, actual_alert.number
      assert_equal "password", actual_alert.label
      assert_equal "Password", actual_alert.token_type
      assert_equal :TOKEN_VALIDITY_ACTIVE, actual_alert.validity
      assert_equal @validity_last_checked, actual_alert.validity_last_checked
      assert_equal actual_payload[:repository][:owner_type], "ORGANIZATION"
      assert actual_payload[:show_generic_secrets_feedback_notice]
      assert_equal actual_payload[:generic_secrets_feedback_notice], "ai_detected_secret_scanning_feedback"
    end

    context "delegated alert closures payload" do
      test "returns false/0 when feature is disabled" do
        token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
        actual_payload = @payload_builder.page_payload(token, 1)

        refute actual_payload[:delegated_closures_enabled]
        assert_equal 0, actual_payload[:existing_closure_request_number]
        refute actual_payload[:show_closure_request_review_buttons]
        refute actual_payload[:existing_closure_request_pending]
      end

      test "returns correct data when feature is enabled with no existing request" do
        SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Services::DelegatedAlertClosuresService.any_instance.stubs(:existing_alert_closure_request).returns(nil)
        token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
        actual_payload = @payload_builder.page_payload(token, 1)

        assert actual_payload[:delegated_closures_enabled]
        assert_equal 0, actual_payload[:existing_closure_request_number]
        refute actual_payload[:show_closure_request_review_buttons]
        refute actual_payload[:existing_closure_request_pending]
      end

      test "returns correct data when feature is enabled with an existing approved request" do
        check_non_pending_request(Exemptions::ExemptionResponse::STATUSES[:approved])
      end

      test "returns correct data when feature is enabled with an existing rejected request" do
        check_non_pending_request(Exemptions::ExemptionResponse::STATUSES[:rejected])
      end

      test "returns correct data when feature is enabled with an existing pending request" do
        SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:enabled?).returns(true)
        closure_request = Exemptions::ExemptionRequest.new(number: 10)
        SecretScanning::Services::DelegatedAlertClosuresService.any_instance.stubs(:existing_alert_closure_request).returns(closure_request)
        SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:display_review_buttons_for_closure_request?).returns(true)

        token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
        actual_payload = @payload_builder.page_payload(token, 1)

        assert actual_payload[:delegated_closures_enabled]
        assert_equal 10, actual_payload[:existing_closure_request_number]
        assert actual_payload[:show_closure_request_review_buttons]
        assert actual_payload[:existing_closure_request_pending]
      end

      test "returns correct data for closed alert" do
        SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:enabled?).returns(true)
        SecretScanning::Services::DelegatedAlertClosuresService.any_instance.stubs(:existing_alert_closure_request).returns(nil)
        token = GitHub::TokenScanning::Service::Token.new(@resolved_token_from_api, @repo)
        actual_payload = @payload_builder.page_payload(token, 1)

        assert actual_payload[:delegated_closures_enabled]
        assert_equal 0, actual_payload[:existing_closure_request_number]
        refute actual_payload[:show_closure_request_review_buttons]
        refute actual_payload[:existing_closure_request_pending]
      end
    end
  end

  def check_non_pending_request(status)
    SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:enabled?).returns(true)
    closure_request = Exemptions::ExemptionRequest.new(id: 1, number: 10, request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE)
    Exemptions::Evaluators::SecretScanningClosureRequestBypass.any_instance.stubs(:is_valid_reviewer?).returns(true)
    Exemptions::ExemptionResponse.create!(exemption_request: closure_request, status: status, reviewer: @user, message: "comment")
    SecretScanning::Services::DelegatedAlertClosuresService.any_instance.stubs(:existing_alert_closure_request).returns(closure_request)
    SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:display_review_buttons_for_closure_request?).returns(true)

    token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
    actual_payload = @payload_builder.page_payload(token, 1)

    assert actual_payload[:delegated_closures_enabled]
    assert_equal 10, actual_payload[:existing_closure_request_number]
    assert actual_payload[:show_closure_request_review_buttons]
    refute actual_payload[:existing_closure_request_pending]
  end

  context "timeline payload" do
    test "includes validity change events" do
      SecretScanning::Models::React::ShowPayloadBuilder.stub_const(:TIMELINE_EVENTS_INITIAL_SHOW_COUNT, 1) do
        SecretScanning::Models::React::ShowPayloadBuilder.stub_const(:TIMELINE_EVENTS_LIMIT, 2) do
          timeline_response = GitHub::Proto::SecretScanning::Api::V2::GetTimelineResponse.new(
            total_number_of_events: 5,
            earliest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
              events: [],
              cursor: nil
            ),
            latest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
              events: [
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :ALERT_CREATION,
                  time: Time.parse("2022-10-21"),
                ),
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :RESOLUTION,
                  time: Time.parse("2022-10-21"),
                  actor: @user.id,
                  resolution: GitHub::Proto::SecretScanning::Api::V2::ResolutionEvent.new(
                    type: :USED_IN_TESTS,
                    resolved: true,
                    resolved_state_change: false,
                    comment: "this alert is used in tests"
                  )
                ),
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :VALIDITY_CHANGE,
                  time: Time.parse("2022-10-21"),
                  actor: 0,
                  validity: GitHub::Proto::SecretScanning::Api::V2::ValidityEvent.new(
                    validity: :TOKEN_VALIDITY_ACTIVE
                  )
                ),
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :VALIDITY_CHANGE,
                  time: Time.parse("2022-10-21"),
                  actor: 0,
                  validity: GitHub::Proto::SecretScanning::Api::V2::ValidityEvent.new(
                    validity: :TOKEN_VALIDITY_INACTIVE
                  )
                ),
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :RESOLUTION,
                  time: Time.parse("2022-10-21"),
                  actor: @user.id,
                  resolution: GitHub::Proto::SecretScanning::Api::V2::ResolutionEvent.new(
                    type: :REVOKED,
                    resolved: true,
                    resolved_state_change: false,
                    comment: "this alert is revoked"
                  )
                ),
              ],
              cursor: nil
            ),
          )

          expected_payload = {
            events_count: 5,
            latest_events: [
              {
                type: :RESOLUTION,
                time: Time.parse("2022-10-21"),
                actor: {
                  avatar_url: @user.primary_avatar_url,
                  display_login: @user.display_login,
                },
                resolution: {
                  type: "revoked",
                  comment: "this alert is revoked"
                }
              }
            ],
            earliest_events: [
              {
                type: :ALERT_CREATION,
                time: Time.parse("2022-10-21"),
              }
            ],
            hidden_events: [
              {
                type: :RESOLUTION,
                time: Time.parse("2022-10-21"),
                actor: {
                  avatar_url: @user.primary_avatar_url,
                  display_login: @user.display_login,
                },
                resolution: {
                  type: "used_in_tests",
                  comment: "this alert is used in tests"
                }
              },
              {
                type: :VALIDITY_CHANGE,
                time: Time.parse("2022-10-21"),
                validity: {
                  validity: :TOKEN_VALIDITY_ACTIVE
                }
              },
              {
                type: :VALIDITY_CHANGE,
                time: Time.parse("2022-10-21"),
                validity: {
                  validity: :TOKEN_VALIDITY_INACTIVE
                }
              },
            ]
          }

          token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
          actual_payload = @payload_builder.timeline_payload(token, timeline_response)

          assert_equal expected_payload, actual_payload
        end
      end
    end

    test "includes alert dismissal requests" do
      SecretScanning::Models::React::ShowPayloadBuilder.stub_const(:TIMELINE_EVENTS_INITIAL_SHOW_COUNT, 1) do
        SecretScanning::Models::React::ShowPayloadBuilder.stub_const(:TIMELINE_EVENTS_LIMIT, 3) do
          timeline_response = GitHub::Proto::SecretScanning::Api::V2::GetTimelineResponse.new(
            total_number_of_events: 3,
            earliest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
              events: [],
              cursor: nil
            ),
            latest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
              events: [
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :ALERT_CREATION,
                  time: Time.parse("2022-10-21"),
                ),
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :DELEGATED_ALERT_CLOSURE_REQUEST_OPENED,
                  time: Time.parse("2022-10-21"),
                  actor: @user.id,
                    exemption_request: GitHub::Proto::SecretScanning::Api::V2::ExemptionRequestEvent.new(
                      requester_comment: "this alert is used in tests",
                      reason: GitHub::Proto::SecretScanning::Api::V1::ExemptionReason::EXEMPTION_REASON_USED_IN_TESTS
                    )
                ),
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :DELEGATED_ALERT_CLOSURE_REQUEST_REJECTED,
                  time: Time.parse("2022-10-21"),
                  actor: @user.id,
                    exemption_response: GitHub::Proto::SecretScanning::Api::V2::ExemptionResponseEvent.new(
                      reviewer_comment: "sorry, i can't allow this",
                    )
                ),
              ],
              cursor: nil
            ),
          )

          expected_payload = {
            events_count: 3,
            latest_events: [
              {
                type: :ALERT_CREATION,
                time: Time.parse("2022-10-21"),
              },
              {
                type: :DELEGATED_ALERT_CLOSURE_REQUEST_OPENED,
                time: Time.parse("2022-10-21"),
                actor: {
                  avatar_url: @user.primary_avatar_url,
                  display_login: @user.display_login,
                },
                  exemption_request: {
                    requester_comment: "this alert is used in tests",
                    reason: "used_in_tests",
                  }
              },
              {
                type: :DELEGATED_ALERT_CLOSURE_REQUEST_REJECTED,
                time: Time.parse("2022-10-21"),
                actor: {
                  avatar_url: @user.primary_avatar_url,
                  display_login: @user.display_login,
                },
                  exemption_response: {
                    reviewer_comment: "sorry, i can't allow this",
                  }
              },

            ],
            earliest_events: [],
            hidden_events: [],
          }

          token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
          actual_payload = @payload_builder.timeline_payload(token, timeline_response)

          assert_equal expected_payload, actual_payload
        end
      end
    end

    test "get timeline payload" do
      SecretScanning::Models::React::ShowPayloadBuilder.stub_const(:TIMELINE_EVENTS_INITIAL_SHOW_COUNT, 1) do
        SecretScanning::Models::React::ShowPayloadBuilder.stub_const(:TIMELINE_EVENTS_LIMIT, 2) do
          timeline_response = GitHub::Proto::SecretScanning::Api::V2::GetTimelineResponse.new(
            total_number_of_events: 3,
            earliest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
              events: [],
              cursor: nil
            ),
            latest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
              events: [
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :ALERT_CREATION,
                  time: Time.parse("2022-10-21"),
                ),
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :RESOLUTION,
                  time: Time.parse("2022-10-21"),
                  actor: @user.id,
                  resolution: GitHub::Proto::SecretScanning::Api::V2::ResolutionEvent.new(
                    type: :USED_IN_TESTS,
                    resolved: true,
                    resolved_state_change: false,
                    comment: "this alert is used in tests"
                  )
                ),
                GitHub::Proto::SecretScanning::Api::V2::TimelineEvent.new(
                  type: :RESOLUTION,
                  time: Time.parse("2022-10-21"),
                  actor: @user.id,
                  resolution: GitHub::Proto::SecretScanning::Api::V2::ResolutionEvent.new(
                    type: :REVOKED,
                    resolved: true,
                    resolved_state_change: false,
                    comment: "this alert is revoked"
                  )
                ),
              ],
              cursor: nil
            ),
          )

          expected_payload = {
            events_count: 3,
            latest_events: [
              {
                type: :RESOLUTION,
                time: Time.parse("2022-10-21"),
                actor: {
                  avatar_url: @user.primary_avatar_url,
                  display_login: @user.display_login,
                },
                resolution: {
                  type: "revoked",
                  comment: "this alert is revoked"
                }
              }
            ],
            earliest_events: [
              {
                type: :ALERT_CREATION,
                time: Time.parse("2022-10-21"),
              }
            ],
            hidden_events: [
              {
                type: :RESOLUTION,
                time: Time.parse("2022-10-21"),
                actor: {
                  avatar_url: @user.primary_avatar_url,
                  display_login: @user.display_login,
                },
                resolution: {
                  type: "used_in_tests",
                  comment: "this alert is used in tests"
                }
              }
            ]
          }

          token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
          actual_payload = @payload_builder.timeline_payload(token, timeline_response)

          assert_equal expected_payload, actual_payload
        end
      end
    end
  end

  context "locations_payload" do
    test "locations payload" do
      token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo, LocationInfoMock.new(included_locations: [@location], commit_oids: [@location.commit_oid]))
      actual_payload = @payload_builder.locations_payload(token)

      refute_empty actual_payload
    end

    test "repo location payload" do
      commit_oid, blob_oid, location_payload = create_repo_location_payload(
        start_line: 1,
        end_line: 2,
        use_real_commit_oid: true,
        use_real_blob_oid: true)

      assert_equal(location_payload[:content_type], :REPOSITORY_BLOB)
      assert_equal(location_payload[:path], "File.txt")
      assert_equal(location_payload[:start_line], 1)
      assert_equal(location_payload[:end_line], 2)
      assert_equal(location_payload[:enable_commit_and_blob_links], true)

      blob = location_payload[:blob]
      assert_equal(blob[:oid], blob_oid)
      assert_equal(blob[:link_accessible], true)

      commit = location_payload[:commit]
      assert_equal(commit[:oid], commit_oid)
      assert_equal(commit[:message], "hardcode secret")
      refute_nil(commit[:created_at])
    end

    test "locations payload has no blob when blob cannot be found" do
      _, _, location_payload = create_repo_location_payload(
        start_line: 1,
        end_line: 2,
        use_real_commit_oid: true,
        use_real_blob_oid: false)
      assert_nil location_payload[:blob]
    end

    test "repo location payload has no blob when location in archive" do
      # archived token locations have start line and end line of 0
      commit_oid, blob_oid, location_payload = create_repo_location_payload(
        start_line: 0,
        end_line: 0,
        use_real_commit_oid: true,
        use_real_blob_oid: true)
      assert_nil(location_payload[:blob])
    end

    test "locations payload is missing commit details when commit cannot be found" do
      _, _, location_payload = create_repo_location_payload(
        start_line: 1,
        end_line: 2,
        use_real_commit_oid: false,
        use_real_blob_oid: true)

      commit = location_payload[:commit]
      refute_nil(commit)
      assert_nil(commit[:message])
      assert_nil(commit[:created_at])
    end

    test "locations payload has blob even if blob is truncated" do
      TreeEntry.any_instance.stubs(:truncated?).returns(true)

      _, _, location_payload = create_repo_location_payload(
        start_line: 1,
        end_line: 2,
        use_real_commit_oid: true,
        use_real_blob_oid: true)

      blob = location_payload[:blob]
      refute_nil(blob)
      assert_equal(blob[:is_truncated], true)
    end

    test "locations payload has blob even if blob is not text" do
      TreeEntry.any_instance.stubs(:text?).returns(false)

      _, _, location_payload = create_repo_location_payload(
        start_line: 1,
        end_line: 2,
        use_real_commit_oid: true,
        use_real_blob_oid: true)

      blob = location_payload[:blob]
      refute_nil(blob)
      assert_equal(blob[:is_text], false)
    end

    test "wiki location payload" do
      path = "Home.md"
      commit_message = "create home page"
      commit_oid, blob_oid, location_payload = create_wiki_location_payload(
        path: path,
        commit_message: commit_message,
        wikis_currently_enabled: true)

      assert_equal(location_payload[:content_type], :WIKI_BLOB)
      assert_equal(location_payload[:path], path)
      assert_equal(location_payload[:start_line], 0)
      assert_equal(location_payload[:end_line], 1)
      assert_equal(location_payload[:enable_commit_and_blob_links], true)

      blob = location_payload[:blob]
      assert_equal(blob[:oid], blob_oid)
      assert_equal(blob[:link_accessible], true)

      commit = location_payload[:commit]
      assert_equal(commit[:oid], commit_oid)
      assert_equal(commit[:message], commit_message)
    end

    test "blob and commits links are not enabled when wiki is disabled" do
      path = "Home.md"
      commit_message = "create home page"
      commit_oid, blob_oid, location_payload = create_wiki_location_payload(
        path: path,
        commit_message: commit_message,
        wikis_currently_enabled: false)

      assert_equal(location_payload[:content_type], :WIKI_BLOB)
      assert_equal(location_payload[:path], path)
      assert_equal(location_payload[:enable_commit_and_blob_links], false)

      blob = location_payload[:blob]
      assert_equal(blob[:oid], blob_oid)
      assert_equal(blob[:link_accessible], true)

      commit = location_payload[:commit]
      assert_equal(commit[:oid], commit_oid)
    end

    test "blob link is not accessible when location is in a file with unsupported format for wikis" do
      path = "Home.txt"
      commit_message = "create home page as text file that is not supported by wikis"
      commit_oid, blob_oid, location_payload = create_wiki_location_payload(
        path: path,
        commit_message: commit_message,
        wikis_currently_enabled: true)

      assert_equal(location_payload[:content_type], :WIKI_BLOB)
      assert_equal(location_payload[:path], path)
      assert_equal(location_payload[:enable_commit_and_blob_links], true)

      blob = location_payload[:blob]
      assert_equal(blob[:oid], blob_oid)
      assert_equal(blob[:link_accessible], false)
    end

    test "blob link is not accessible using full location path when location is in a subdirectory" do
      path = "subdir/Home.txt"
      commit_message = "create home page in subdirectory"
      commit_oid, blob_oid, location_payload = create_wiki_location_payload(
        path: path,
        commit_message: commit_message,
        wikis_currently_enabled: true)

      assert_equal(location_payload[:content_type], :WIKI_BLOB)
      assert_equal(location_payload[:path], path)
      assert_equal(location_payload[:enable_commit_and_blob_links], true)

      blob = location_payload[:blob]
      assert_equal(blob[:oid], blob_oid)
      assert_equal(blob[:link_accessible], false)
    end

    test "locations payload slices blob content properly when secret is at the top of the file" do
      _, _, location_payload = create_repo_location_payload(
        start_line: 1,
        end_line: 2,
        use_real_commit_oid: true,
        use_real_blob_oid: true)
      blob_preview_lines =  location_payload[:blob][:lines]

      assert_equal %w[line1 line2 line3 line4 line5 line6 line7], blob_preview_lines
    end

    test "locations payload slices blob content properly when secret is in the middle of the file" do
      _, _, location_payload = create_repo_location_payload(
        start_line: 11,
        end_line: 12,
        use_real_commit_oid: true,
        use_real_blob_oid: true)
      blob_preview_lines =  location_payload[:blob][:lines]

      assert_equal %w[line6 line7 line8 line9 line10 line11 line12 line13 line14 line15 line16 line17], blob_preview_lines
    end

    test "locations payload slices blob content properly when secret is at the end of the file" do
      _, _, location_payload = create_repo_location_payload(
        start_line: 19,
        end_line: 20,
        use_real_commit_oid: true,
        use_real_blob_oid: true)
      blob_preview_lines = location_payload[:blob][:lines]

      assert_equal %w[line14 line15 line16 line17 line18 line19 line20], blob_preview_lines
    end
  end

  context "resolve alerts" do
    test "resolve alerts allowed for org admin" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

      payload = SecretScanning::Models::React::ShowPayloadBuilder.new(@repo, @user)
      token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
      actual_payload = payload.page_payload(token, 1)

      assert_equal true, T.must(actual_payload)[:resolve_alerts_allowed]
    end

    test "resolve alerts not allowed for user that can only view secret scanning alerts" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

      # stub the commit since we now look through commits for the author email
      @repo.stubs(:find_commit).returns(CommitMock.new(author_email: "secret_author@github.com", author_emails: ["secret_author@github.com"]))

      view_secret_scanning_alerts_payload = SecretScanning::Models::React::ShowPayloadBuilder.new(@repo, @view_secret_scanning_alerts_user)
      token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
      actual_payload = view_secret_scanning_alerts_payload.page_payload(token, 1)

      assert_equal false, T.must(actual_payload)[:resolve_alerts_allowed]
    end

    test "resolve alerts allowed for user that commits secret and views associated alert" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

      # stub the commit since we now look through commits for the author email
      @repo.stubs(:find_commit).returns(CommitMock.new(author_email: "secret_author@github.com", author_emails: ["secret_author@github.com"]))

      payload = SecretScanning::Models::React::ShowPayloadBuilder.new(@repo, @secret_author)
      token = GitHub::TokenScanning::Service::Token.new(@secret_author_token_from_api, @repo)
      actual_payload = payload.page_payload(token, 1)

      assert T.must(actual_payload)[:resolve_alerts_allowed]
    end

    test "resolve alerts allowed for user that commits wiki secret and views associated alert" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

      # stub the commit since we now look through commits for the author email
      @repo.stubs(:find_commit).returns(nil)
      @repo.stubs(:find_wiki_commit).returns(CommitMock.new(author_email: "secret_author@github.com", author_emails: ["secret_author@github.com"]))

      payload = SecretScanning::Models::React::ShowPayloadBuilder.new(@repo, @secret_author)
      token = GitHub::TokenScanning::Service::Token.new(@secret_author_token_from_api, @repo)
      actual_payload = payload.page_payload(token, 1)

      assert T.must(actual_payload)[:resolve_alerts_allowed]
    end
  end

  context "custom pattern from alert" do
    test "repo admins and security managers can access repo-scoped custom pattern from alert" do
      response = @payload_builder.can_access_custom_pattern?(test_custom_pattern_data)

      assert response

      response = @security_manager_payload_builder.can_access_custom_pattern?(test_custom_pattern_data)

      assert response
    end

    test "org admins and security managers can access org-scoped custom pattern from alert" do
      response = @payload_builder.can_access_custom_pattern?(test_custom_pattern_data(:ORGANIZATION_SCOPE))

      assert response

      response = @security_manager_payload_builder.can_access_custom_pattern?(test_custom_pattern_data(:ORGANIZATION_SCOPE))

      assert response
    end

    test "business-scoped custom pattern cannot be accessed from alert" do
      response = @payload_builder.can_access_custom_pattern?(test_custom_pattern_data(:BUSINESS_SCOPE))

      refute response
    end
  end

  context "token metadata" do
    test "link to token is available if owner is viewer" do
      token_metadata = token_metadata = SecretScanning::Models::GitHubTokenMetadata.new(
        created_at: Time.now,
        expires_at: Time.now + 1.day,
        last_accessed_at: Time.now + 1.hour,
        org_access: nil,
        token_type: "GITHUB",
        access_id: 1,
        owner_id: @user.id,
        name: "token",
        link: "/foo/bar/token",
      )
      token_link = @payload_builder.get_token_link(token_metadata)

      assert_equal "/foo/bar/token", token_link
    end

    test "link to token is unavailable if owner is viewer" do
      token_metadata = token_metadata = SecretScanning::Models::GitHubTokenMetadata.new(
        created_at: Time.now,
        expires_at: Time.now + 1.day,
        last_accessed_at: Time.now + 1.hour,
        org_access: nil,
        token_type: "GITHUB",
        access_id: 1,
        owner_id: @user2.id,
        name: "token",
        link: "/foo/bar/token",
      )
      token_link = @payload_builder.get_token_link(token_metadata)

      assert_nil token_link
    end
  end

  def test_custom_pattern_data(scope = :REPOSITORY_SCOPE)
    pattern_data = GitHub::Proto::SecretScanning::Api::V2::GetTokenResponse::CustomPatternData.new({
      custom_pattern_id: 1,
      owner_scope: scope
    })

    case scope
    when :REPOSITORY_SCOPE
      pattern_data.owner_id = @repo.id
    when :ORGANIZATION_SCOPE
      pattern_data.owner_id = @org.id
    when :BUSINESS_SCOPE
      pattern_data.owner_id = 1
    end

    pattern_data
  end

  def create_repo_location_payload(start_line:, end_line:, use_real_commit_oid:, use_real_blob_oid:)
    # set up repo and payload
    repo = create(:repository, owner: @org, from_example: :with_tokens)
    payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(repo, @user)

    # commit a file with 20 lines
    lines = (1..20).map { |i| "line#{i}" }.join("\n")
    commit = create(:commit, repository: repo, message: "hardcode secret", changes: -> (files) {
      files.add("File.txt", lines)
    })

    # get blob OID
    tree = repo.read_objects([commit.tree_oid], :tree, feature_flag: :show_payload_builder_test).first
    blob_hash = tree["entries"].values.find { |e| e["type"] == "blob" }
    blob_oid = blob_hash["oid"]

    location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
      created_at: Time.parse("2022-10-21"),
      commit_oid: use_real_commit_oid ? commit.oid : "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
      blob_oid: use_real_blob_oid ? blob_oid : "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
      content_type: :REPOSITORY_BLOB,
      start_line: start_line,
      end_line: end_line,
      path: "File.txt"
    )

    token = GitHub::TokenScanning::Service::Token.new(
      @token_from_api,
      repo,
      LocationInfoMock.new(
        included_locations: [location],
        commit_oids: [commit.oid]
      )
    )

    [commit.oid, blob_oid, payload_builder.locations_payload(token)&.first]
  end

  def setup_wiki(wikis_currently_enabled:)
    # setup repo, wiki
    repo = create(:repository, owner: @org, from_example: :with_tokens, has_wiki: wikis_currently_enabled)

    repo.initialize_wiki(repo.owner)
    wiki = repo.unsullied_wiki

    # add initial commit to wiki to create a branch so that we can use create(:commit)
    wiki.pages.create "setup wiki", :markdown, "wiki setup contents", "setting up wiki", @secret_author

    [repo, wiki]
  end

  def create_wiki_commit(wiki:, path:, commit_message:)
    commit = create(
      :commit,
      repository: wiki,
      committer: @secret_author,
      message: commit_message,
      changes: -> (files) {
        files.add(path, "contents")
      }
    )

    tree = wiki.read_objects([commit.tree_oid], :tree, feature_flag: :show_payload_builder_test).first
    blob_hash = tree["entries"].values.find { |e| e["type"] == "blob" }
    blob_oid = blob_hash["oid"]

    [commit.oid, blob_oid]
  end

  def token_with_wiki_location(repo:, path:, commit_oid:, blob_oid:)
    proto_location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
      created_at: Time.parse("2022-10-21"),
      commit_oid: commit_oid,
      blob_oid: blob_oid,
      content_type: :WIKI_BLOB,
      start_line: 0,
      end_line: 1,
      path: path,
    )

    proto_token = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2022-10-21"),
      first_location: proto_location,
      id: 1,
      label: "Adafruit IO Key",
      token_type: "adafruit_io_key",
      repository_id: repo.id,
      number: 1,
    )

    GitHub::TokenScanning::Service::Token.new(
      proto_token,
      repo,
      LocationInfoMock.new(
        included_locations: [proto_location],
        commit_oids: [commit_oid]
      )
    )
  end

  def create_wiki_location_payload(path:, commit_message:, wikis_currently_enabled:)
    repo, wiki = setup_wiki(wikis_currently_enabled: wikis_currently_enabled)

    commit_oid, blob_oid = create_wiki_commit(wiki: wiki, path: path, commit_message: commit_message)

    wiki_token = token_with_wiki_location(repo: repo, path: path, commit_oid: commit_oid, blob_oid: blob_oid)

    payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(repo, @user)
    location_payload = payload_builder.locations_payload(wiki_token)&.first

    [commit_oid, blob_oid, location_payload]
  end
end
