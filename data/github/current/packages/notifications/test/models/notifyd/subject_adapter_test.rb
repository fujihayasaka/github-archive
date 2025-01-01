# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class SubjectAdapterTest < GitHub::TestCase
    fixtures do
      @issue = create(:issue)
    end

    context "without an adapter declared" do
      test ".adapter_for_subject raises" do
        assert_raises SubjectAdapter::MissingSubjectAdapterError do
          SubjectAdapter.adapter_for_subject(Object.new)
        end
      end

      test "notification_id_from_subject returns nil" do
        assert SubjectAdapter.notification_id_from_subject(Object.new).nil?
      end

      test "notify_feature_flag_from_subject returns nil" do
        assert SubjectAdapter.notify_feature_flag_from_subject(Object.new).nil?
      end
    end

    context ".adapter_for_subject" do
      test "CheckSuite" do
        user = create(:user)
        check_suite = create(:check_suite, :with_name, :failure, :with_push, pusher: user)

        assert_kind_of Notifyd::CheckSuiteAdapter, SubjectAdapter.adapter_for_subject(check_suite)
      end

      test "MemexProjectStatus" do
        memex_project_status = create(:memex_project_status)

        assert_kind_of Notifyd::MemexProjectStatusAdapter, SubjectAdapter.adapter_for_subject(memex_project_status)
      end
    end

    context "with an incorrect adapter declared" do
      test ".adapter_for_subject returns the adapter" do
        assert_kind_of Notifyd::IssueAdapter, SubjectAdapter.adapter_for_subject(@issue)
      end

      test "notification_id_from_subject raises an exception" do
        Notifyd::IssueAdapter.any_instance.stubs(:notification_id).returns(nil)

        assert_raises(Notifyd::SubjectAdapter::MissingNotificationIdError) do
          SubjectAdapter.notification_id_from_subject(@issue)
        end
      end

      test "notify_feature_flag_from_subject raises an exception" do
        Notifyd::IssueAdapter.any_instance.stubs(:notify_feature_flag).returns(nil)

        assert_raises(Notifyd::SubjectAdapter::MissingFeatureFlagError) do
          SubjectAdapter.notify_feature_flag_from_subject(@issue)
        end
      end
    end

    context "with a correct adapter declared" do
      test ".adapter_for_subject returns the adapter" do
        assert_kind_of Notifyd::IssueAdapter, SubjectAdapter.adapter_for_subject(@issue)
      end

      test "adapter_for_subject sets context on the adapter" do
        context = { my_context: "my_value" }
        response = SubjectAdapter.adapter_for_subject(@issue, context)

        assert_equal context, response.context
      end

      test "notification_id_from_subject returns a notification_id" do
        refute_nil SubjectAdapter.notification_id_from_subject(@issue)
      end

      test "notify_feature_flag_from_subject returns a feature flag" do
        refute_nil SubjectAdapter.notify_feature_flag_from_subject(@issue)
      end
    end

    context "with subject adapter instance enforce method" do
      test "notify_feature_flag" do
        assert_raises Notifyd::SubjectAdapter::MissingFeatureFlagError do
          base_subject_adapter.notify_feature_flag
        end
      end

      test "notification_id" do
        assert_raises Notifyd::SubjectAdapter::MissingNotificationIdError do
          base_subject_adapter.notification_id
        end
      end

      test "authzd_attributes" do
        assert_raises NotImplementedError do
          base_subject_adapter.authzd_attributes
        end
      end

      test "saml_enforcement" do
        assert_raises NotImplementedError do
          base_subject_adapter.saml_enforcement
        end
      end

      test "mobile_layout" do
        assert_raises NotImplementedError do
          base_subject_adapter.mobile_layout
        end
      end

      test "email_layout" do
        assert_raises NotImplementedError do
          base_subject_adapter.email_layout
        end
      end

      test "related_topics" do
        assert_raises NotImplementedError do
          base_subject_adapter.related_topics
        end
      end

      test "explicit_recipients" do
        assert_raises NotImplementedError do
          base_subject_adapter.explicit_recipients
        end
      end

      test "repository_id" do
        assert_raises NotImplementedError do
          base_subject_adapter.repository_id
        end
      end

      test "owner_id" do
        assert_raises NotImplementedError do
          base_subject_adapter.owner_id
        end
      end

      test "matches?" do
        assert base_subject_adapter.matches?
      end

      test "attributes" do
        assert_raises NotImplementedError do
          base_subject_adapter.attributes
        end
      end

      test "trigger" do
        assert_raises NotImplementedError do
          base_subject_adapter.trigger
        end
      end

      test "feature_switches defaults to empty object" do
        assert_equal base_subject_adapter.feature_switches, {}
      end

      test "email_reasons_to_words return reasons to words default mapping" do
        refute_nil base_subject_adapter.email_reasons_to_words[:comment]
        refute_nil base_subject_adapter.email_reasons_to_words[:mention]
        refute_nil base_subject_adapter.email_reasons_to_words[:author]
      end
    end

    context "config" do
      context "reason_groups" do
        test "reason_groups exists" do
          assert_equal base_subject_adapter.reason_groups, [
            { name: "notify_muted", reasons: %w[mention team_mention] },
            { name: "participant", reasons: %w[author comment assign state_change mention team_mention manual] },
          ]
        end
      end
    end

    test "subject adapter resolves plain body as subject body" do
      subject = mock
      subject.stubs(:body).returns("plain_text")
      adapter = SubjectAdapter.new(subject, {})
      assert_equal adapter.subject_body, "plain_text"
    end

    test "subject adapter resolves email html as subject body" do
      subject = mock
      subject.stubs(:body_html_for_email).returns("email_html")
      subject.stubs(:body_html).returns("html")
      subject.stubs(:body).returns("plain_text")
      adapter = SubjectAdapter.new(subject, {})
      assert_equal adapter.subject_body, "email_html"
    end

    test "subject adapter resolves body html as subject body" do
      subject = mock
      subject.stubs(:body_html).returns("html")
      subject.stubs(:body).returns("plain_text")
      adapter = SubjectAdapter.new(subject, {})
      assert_equal adapter.subject_body, "html"
    end

    context "without a valid owner type given" do
      test ".owner_type_enum raises" do
        assert_raises SubjectAdapter::UnknownOwnerTypeError do
          SubjectAdapter.owner_type_enum(:unknown)
        end
      end
    end

    context "with a valid owner type given" do
      test ".owner_type_enum returns :USER for :user" do
        assert_equal(SubjectAdapter.owner_type_enum(:user), :USER)
      end
      test ".owner_type_enum returns :ORGANIZATION for :organization" do
        assert_equal(SubjectAdapter.owner_type_enum(:organization), :ORGANIZATION)
      end
    end

    private

    def base_subject_adapter
      SubjectAdapter.new(@issue, {})
    end
  end
end
