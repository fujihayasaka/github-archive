# typed: true
# frozen_string_literal: true

require "test_helper"

class MarkableAsSpammyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @staffer = create :staff_admin_user
    @user = create(:verified_user)

    @owner = create(:user, login: "the-owner", email: "the-owner@example.com")
    @another_owner = create(:user, login: "another-owner", email: "another-owner@example.com")
    @other_member = create(:user, login: "other-member", email: "other-member@example.com")

    @org = create(:organization, login: "an-org", admin: @owner)
    @org.add_admin(@another_owner)
    @org.add_member(@other_member)

    @business_admin = create(:user)
    @business = create(:business, owners: [@business_admin])
    @business.add_organization(@org)
  end

  setup do
    deliveries.clear
    @user.queue_signup_tasks
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  if GitHub.spamminess_check_enabled?
    context "#mark_as_spammy" do
      test "it truncates spammy_reason to max field size" do
        @user.mark_as_spammy actor: @staffer, reason: "s" * (Spam::MarkableAsSpammy::MAX_SPAMMY_REASON_LENGTH + 1)
        assert @user.spammy_reason.length <= Spam::MarkableAsSpammy::MAX_SPAMMY_REASON_LENGTH
      end
    end

    test "it doesn't send an email to users marked as spammy if the reason for the spam flag is not one that requires notification under the EU DSA (i.e., no dsa_source is provided)" do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "deliveries.size", 0 do
          @user.mark_as_spammy actor: @staffer, reason: "tos", dsa_source: nil
        end
      end
    end

    test "it doesn't send an email to orgs marked as spammy if the reason for the spam flag is not one that requires notification under the EU DSA (i.e., no dsa_source is provided)" do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "deliveries.size", 0 do
          @org.mark_as_spammy actor: @staffer, reason: "tos", dsa_source: nil
        end
      end
    end

    test "it doesn't send an email to business owners, or owners of orgs that are members of businesses marked as spammy if the reason for the spam flag is not one that requires notification under the EU DSA (i.e., no dsa_source is provided)" do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "deliveries.size", 0 do
          @business.mark_as_spammy actor: @staffer, reason: "tos", dsa_source: nil
        end
      end
    end

    context "#mark_as_spammy dsa" do
      test "publishes ModerationAction event when user is marked as spammy" do
        @user.mark_as_spammy(
          actor: @staffer,
          reason: :SCOPE_OF_PLATFORM_SERVICES,
          dsa_source: :USER_REPORT,
          notes: "test",
          content_creation_date: DateTime.parse("2018-01-01"),
          content_formats: ["TEXT"]
        )

        assert_hydro_published({
          action: "staff.mark_as_spammy",
          actor: Hydro::EntitySerializer.user(@staffer),
          account_moderation: {
            account: Hydro::EntitySerializer.user(@user),
            moderation_type: :SUSPENDED,
            end_timestamp: nil
          },
          content_moderation: {
            content_created_at: DateTime.parse("2018-01-01"),
            formats: ["TEXT"]
          },
          countries: nil,
          reason: nil,
          tos_reason: :SCOPE_OF_PLATFORM_SERVICES,
          source: :USER_REPORT,
          is_test: false
        }, schema: "github.moderation.v0.ModerationAction")
      end

      test "publishes ModerationAction event with stripped reason when flagged with orgs" do
        @user.mark_as_spammy(
          actor: @staffer,
          reason: "SCOPE_OF_PLATFORM_SERVICES - flagged with organization",
          dsa_source: :USER_REPORT,
          notes: "test",
          content_creation_date: DateTime.parse("2018-01-01"),
          content_formats: ["TEXT"]
        )

        assert_hydro_published({
          action: "staff.mark_as_spammy",
          actor: Hydro::EntitySerializer.user(@staffer),
          account_moderation: {
            account: Hydro::EntitySerializer.user(@user),
            moderation_type: :SUSPENDED,
            end_timestamp: nil
          },
          content_moderation: {
            content_created_at: DateTime.parse("2018-01-01"),
            formats: ["TEXT"]
          },
          countries: nil,
          reason: nil,
          tos_reason: :SCOPE_OF_PLATFORM_SERVICES,
          source: :USER_REPORT,
          is_test: false
        }, schema: "github.moderation.v0.ModerationAction")
      end

      test "publishes ModerationAction event when a test user is marked as spammy" do
        @staffer.update!(email: "mona@github.com")
        test_user = create(:user, email: "mona+evil@github.com")
        test_user.mark_as_spammy(
          actor: @staffer,
          reason: :SCOPE_OF_PLATFORM_SERVICES,
          dsa_source: :USER_REPORT,
          dsa_moderation_type: :SUSPENDED,
          notes: "test",
          content_creation_date: DateTime.parse("2018-01-01"),
          content_formats: ["TEXT"]
        )

        assert_hydro_published({
          action: "staff.mark_as_spammy",
          actor: Hydro::EntitySerializer.user(@staffer),
          account_moderation: {
            account: Hydro::EntitySerializer.user(test_user),
            moderation_type: :SUSPENDED,
            end_timestamp: nil
          },
          content_moderation: {
            content_created_at: DateTime.parse("2018-01-01"),
            formats: ["TEXT"]
          },
          countries: nil,
          reason: nil,
          source: :USER_REPORT,
          tos_reason: :SCOPE_OF_PLATFORM_SERVICES,
          is_test: true
        }, schema: "github.moderation.v0.ModerationAction")
      end

      test "it sends an email to users marked as spammy if the reason for the spam flag is one that requires notification under the EU DSA (i.e., dsa_source is provided)" do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_difference "deliveries.size", 1 do
            @user.mark_as_spammy actor: @staffer, reason: "DISINFORMATION", dsa_source: "DSA_REPORT"
          end
        end
        mail = ActionMailer::Base.deliveries.pop
        assert_includes mail.text_part.body.to_s, "Your public content is now hidden from other users."
        assert_includes mail.text_part.body.to_s, "we received a notice pursuant to Article 16 of the DSA"
        assert_includes mail.text_part.body.to_s, "You may not post content that presents a distorted view of reality, whether it is inaccurate or false (misinformation) or is intentionally deceptive (disinformation)"
      end

      test "it sends an email to orgs marked as spammy if the reason for the spam flag is one that requires notification under the EU DSA (i.e., dsa_source is provided)" do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_difference "deliveries.size", 1 do
            @org.mark_as_spammy actor: @staffer, reason: "DISINFORMATION", dsa_source: "DSA_REPORT"
          end
        end
        mail = ActionMailer::Base.deliveries.pop
        assert_equal 2, mail.bcc.size
        assert_includes mail.bcc, @owner.email
        assert_includes mail.bcc, @another_owner.email
        assert_includes mail.text_part.body.to_s, "This organization's public content is now hidden from other users."
        assert_includes mail.text_part.body.to_s, "we received a notice pursuant to Article 16 of the DSA"
        assert_includes mail.text_part.body.to_s, "You may not post content that presents a distorted view of reality, whether it is inaccurate or false (misinformation) or is intentionally deceptive (disinformation)"
      end

      test "it sends an email to admins of businesses and owners of orgs that are members of businesses marked as spammy if the reason for the spam flag is one that requires notification under the EU DSA (i.e., dsa_source is provided)" do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob, ToggleSpamFlagOnBusinessOrganizationsJob]) do
          assert_difference "deliveries.size", 1 do
            @business.mark_as_spammy actor: @staffer, reason: "DISINFORMATION", dsa_source: "DSA_REPORT"
          end
        end
        mail = ActionMailer::Base.deliveries.pop
        assert_equal 2, mail.bcc.size
        assert_includes mail.bcc, @owner.email
        assert_includes mail.bcc, @another_owner.email
        assert_includes mail.text_part.body.to_s, "This organization's public content is now hidden from other users."
        assert_includes mail.text_part.body.to_s, "we received a notice pursuant to Article 16 of the DSA"
        assert_includes mail.text_part.body.to_s, "You may not post content that presents a distorted view of reality, whether it is inaccurate or false (misinformation) or is intentionally deceptive (disinformation)"
      end
    end
  end
end
