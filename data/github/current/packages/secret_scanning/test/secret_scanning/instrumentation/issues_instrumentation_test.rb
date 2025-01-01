# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Instrumentation
  class IssuesInstrumentationTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @user = create(:user)
      @repo = create(:repository)
    end

    context "Create issue" do
      test "hydro payload includes Issue Scanning TSS feature flags" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:issue_scanning_service_flags).returns(expected_flags)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        expected_message = {
          feature_flags: expected_flags,
        }


        GlobalInstrumenter.instrument(
          "issue.create",
          actor: @user,
          repository: @repo,
          repository_owner: @repo.owner,
          issue: issue,
          title: issue.title,
          body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes encrypted content" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        expected_message = {
          content_id: issue.id,
          content_number: issue.number,
        }

        GlobalInstrumenter.instrument(
          "issue.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          repository_owner: @repo.owner,
          title: issue.title,
          body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes created at" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        expected_message = {
          content_created_at: issue.created_at.getutc
        }

        GlobalInstrumenter.instrument(
          "issue.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          repository_owner: @repo.owner,
          title: issue.title,
          body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "encryption argument error handled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        SecretScanning::Encryption::EncryptedUserContentCryptoHelper.stubs(:try_get_encrypted_content_encryption_keys).raises(ArgumentError.new("Invalid argument"))
        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        expected_message = {}

        GlobalInstrumenter.instrument(
          "issue.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          repository_owner: @repo.owner,
          title: issue.title,
          body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "no hydro message when Issue Scanning disabled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)
        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        GlobalInstrumenter.instrument(
          "issue.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          repository_owner: @repo.owner,
          title: issue.title,
          body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          refute_hydro_messages(schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Update issue" do
      test "hydro payload includes Issue Scanning TSS feature flags" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:issue_scanning_service_flags).returns(expected_flags)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "issue.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          current_title: issue.title,
          current_body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes encrypted content" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        expected_message = {
          content_id: issue.id,
          content_number: issue.number,
        }

        GlobalInstrumenter.instrument(
          "issue.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          current_title: issue.title,
          current_body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes created timestamp" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        expected_message = {
          content_created_at: issue.created_at.getutc
        }

        GlobalInstrumenter.instrument(
          "issue.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          current_title: issue.title,
          current_body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "encryption argument error handled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        SecretScanning::Encryption::EncryptedUserContentCryptoHelper.stubs(:try_get_encrypted_content_encryption_keys).raises(ArgumentError.new("Invalid argument"))
        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        expected_message = {}

        GlobalInstrumenter.instrument(
          "issue.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          current_title: issue.title,
          current_body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "no hydro message when Issue Scanning disabled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)
        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        GlobalInstrumenter.instrument(
          "issue.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          current_title: issue.title,
          current_body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          refute_hydro_messages(schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Create issue comment" do
      test "hydro payload includes Issue Scanning TSS feature flags" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:issue_scanning_service_flags).returns(expected_flags)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "issue_comment.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes encrypted content" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        expected_message = {
          content_id: issue_comment.id,
          content_number: issue.number,
        }

        GlobalInstrumenter.instrument(
          "issue_comment.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes created at" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        expected_message = {
          content_created_at: issue_comment.created_at.getutc
        }

        GlobalInstrumenter.instrument(
          "issue_comment.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "encryption argument error handled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        SecretScanning::Encryption::EncryptedUserContentCryptoHelper.stubs(:try_get_encrypted_content_encryption_keys).raises(ArgumentError.new("Invalid argument"))

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        expected_message = {}

        GlobalInstrumenter.instrument(
          "issue_comment.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "no hydro message when Issue Scanning disabled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        GlobalInstrumenter.instrument(
          "issue_comment.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          refute_hydro_messages(schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Update issue comment" do
      test "hydro payload includes Issue Scanning TSS feature flags" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        expected_flags = %w[flag1 flag2 flag3]
        SecretScanning::Instrumentation::RepositoryServiceFlags.any_instance.stubs(:issue_scanning_service_flags).returns(expected_flags)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        expected_message = {
          feature_flags: expected_flags,
        }

        GlobalInstrumenter.instrument(
          "issue_comment.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes encrypted content" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        expected_message = {
          content_id: issue_comment.id,
          content_number: issue.number,
        }

        GlobalInstrumenter.instrument(
          "issue_comment.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes content created at" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        expected_message = {
          content_created_at: issue_comment.created_at.getutc
        }

        GlobalInstrumenter.instrument(
          "issue_comment.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "encryption argument error handled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        SecretScanning::Encryption::EncryptedUserContentCryptoHelper.stubs(:try_get_encrypted_content_encryption_keys).raises(ArgumentError.new("Invalid argument"))

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        expected_message = {}

        GlobalInstrumenter.instrument(
          "issue_comment.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published_partial(expected_message, schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "no hydro message when Issue Scanning disabled" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        GlobalInstrumenter.instrument(
          "issue_comment.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          refute_hydro_messages(schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end

    context "Exception handling" do
      test "handles unexpected exception for issue" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)
        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)

        SecretScanning::Encryption::EncryptedUserContentHelper.stubs(:encrypt_user_content).raises(ArgumentError.new("Invalid argument"))
        Failbot.expects(:report).with(instance_of(ArgumentError))

        GlobalInstrumenter.instrument(
          "issue.create",
          actor: @user,
          repository: @repo,
          issue: issue,
          repository_owner: @repo.owner,
          title: issue.title,
          body: issue.body,
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          refute_hydro_messages(schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end

      test "hydro payload includes encrypted content" do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(true)

        SecretScanning::Encryption::EncryptedUserContentHelper.stubs(:encrypt_user_content).raises(ArgumentError.new("Invalid argument"))
        Failbot.expects(:report).times(2).with(instance_of(ArgumentError))

        issue = create(:issue, user: @user, title: "Hello", body: "World", repository: @repo)
        issue_comment = create(:issue_comment, body: "Beep boop beep, I'm a robot", issue: issue)

        GlobalInstrumenter.instrument(
          "issue_comment.update",
          actor: @user,
          repository: @repo,
          issue: issue,
          issue_comment: issue_comment
        )

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          refute_hydro_messages(schema: "github.secret_scanning.v1.EncryptedContentScanEvent")
        end
      end
    end
  end
end
