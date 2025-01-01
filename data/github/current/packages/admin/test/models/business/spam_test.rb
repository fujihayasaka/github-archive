# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSpamTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @rando = create :user
    @owner_one = create :user
    @owner_two = create :user
    @member_org_one = create :organization
    @member_org_two = create :organization
    @business = create :business,
      owners: [@owner_one, @owner_two],
      organizations: [@member_org_one, @member_org_two]
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "#spammy?" do
    if GitHub.spamminess_check_enabled?
      test "returns true when marked spammy" do
        @business.update! spammy: true
        assert_predicate @business, :spammy?
      end

      test "returns false when not marked spammy" do
        @business.update! spammy: false
        refute_predicate @business, :spammy?
      end
    else
      test "always returns false when spamminess check disabled" do
        @business.update! spammy: true
        refute_predicate @business, :spammy?
      end
    end
  end

  if GitHub.spamminess_check_enabled?
    context "#mark_as_hammy" do
      test "ensures account cannot be marked spammy once allowlisted" do
        refute_predicate @business, :hammy?

        @business.mark_as_hammy
        assert_predicate @business, :hammy?

        @business.mark_as_spammy
        refute_predicate @business, :spammy?
      end
    end

    context "#mark_as_spammy" do
      test "marks a Business as spammy" do
        @business.mark_as_spammy
        assert_predicate @business, :spammy?
      end

      test "marks all Organizations within the Business as spammy" do
        perform_enqueued_jobs only: ToggleSpamFlagOnBusinessOrganizationsJob do
          @business.mark_as_spammy
        end

        assert_predicate @business, :spammy?
        assert_predicate @member_org_one.reload, :spammy?
        assert_predicate @member_org_two.reload, :spammy?
      end

      test "works for a Business that is already marked spammy" do
        @business.update! spammy: true

        @business.mark_as_spammy

        assert_predicate @business, :spammy?
      end

      test "instruments staff.mark_as_spammy audit log event" do
        Timecop.freeze do
          events = subscribe "staff.mark_as_spammy"
          reason = "Did spammy things"
          staffer = create :staff_admin_user
          @business.mark_as_spammy actor: staffer, reason: reason

          expected_payload = {
            business:                  @business.slug,
            business_id:               @business.id,
            name:                      @business.slug,
            reason:                    "#{reason} by @#{staffer.login}",
            previously_spammy:         false,
            currently_spammy:          true,
            origin:                    :DOTCOM,
            spammy_classification:     "analyst-0",
            spammy_classifier_type:    "analyst",
            spammy_classifier_id:      0,
            subject:                   "unknown",
            staff_actor:               staffer.login,
            staff_actor_id:            staffer.id,
            actor:                     User.staff_user.to_s,
            actor_id:                  User.staff_user.id,
            hard_flag:                 nil,
          }

          assert event = events.pop, "a staff.mark_as_spammy event was expected"
          assert_equal "staff.mark_as_spammy", event.name
          assert_equal expected_payload, event.payload
          assert_equal 1, GitHub.dogstats.increments("business.mark_as_spammy").length
        end
      end

      test "publishes an abuse classification Hydro event" do
        now = Time.parse("2018-01-01")

        Timecop.freeze(now) do
          analyst = create :user, login: "triage-worker"

          @business.mark_as_spammy(actor: analyst, reason: "sketchy")

          message = {
            request_context: nil,
            actor: Hydro::EntitySerializer.user(analyst),
            business: Hydro::EntitySerializer.business(@business),
            previous_classification: :NONE,
            current_classification: :SPAMMY,
            previous_spammy_reason: { value: "" },
            current_spammy_reason: { value: "sketchy by @triage-worker" },
            previously_suspended: { value: false },
            currently_suspended: { value: false },
            currently_deleted: { value: false },
            origin: :DOTCOM,
            queue_action: :QUEUE_ACTION_NONE,
            queue_entry: nil,
            previous_queue: nil,
            current_queue: nil,
            queued_time_in_seconds: nil,
          }

          assert_hydro_published message, schema: "github.v1.EnterpriseAbuseClassification"
          assert_hydro_messages count: 1, schema: "github.v1.EnterpriseAbuseClassification"
        end
      end
    end

    context "#mark_not_spammy" do
      test "marks a Business as not spammy" do
        @business.mark_as_spammy
        assert_predicate @business, :spammy?

        @business.mark_not_spammy

        refute_predicate @business, :spammy?
        refute_predicate @business, :hammy?
      end


      test "marks all Organizations within the Business as not spammy" do
        perform_enqueued_jobs only: ToggleSpamFlagOnBusinessOrganizationsJob do
          @business.mark_as_spammy
        end
        assert_predicate @business, :spammy?
        assert_predicate @member_org_one.reload, :spammy?
        assert_predicate @member_org_two.reload, :spammy?

        perform_enqueued_jobs only: ToggleSpamFlagOnBusinessOrganizationsJob do
          @business.mark_not_spammy
        end

        refute_predicate @business, :spammy?
        refute_predicate @business, :hammy?
        refute_predicate @member_org_one.reload, :spammy?
        refute_predicate @member_org_two.reload, :spammy?
      end

      test "with whitelist true clears spamminess and whitelists the Business" do
        @business.mark_as_spammy
        assert_predicate @business, :spammy?

        @business.mark_not_spammy(whitelist: true)

        refute_predicate @business, :spammy?
        assert_predicate @business, :hammy?
      end

      test "instruments staff.mark_not_spammy audit log event" do
        old_reason = "Did spammy things"
        @business.mark_as_spammy reason: old_reason
        assert_predicate @business, :spammy?

        Timecop.freeze do
          events = subscribe "staff.mark_not_spammy"
          staffer = create :staff_admin_user
          @business.mark_not_spammy actor: staffer, whitelist: true

          expected_payload = {
            name:                      @business.slug,
            previously_spammy:         true,
            currently_spammy:          false,
            previous_spammy_reason:    old_reason,
            origin:                    :DOTCOM,
            subject:                   "unknown",
            spammy_classification:     "unclassified-0",
            spammy_classifier_type:    "unclassified",
            spammy_classifier_id:      0,
            whitelist:                 true,
            note:                      "Old reason: #{old_reason}",
            staff_actor:               staffer.login,
            staff_actor_id:            staffer.id,
            actor:                     User.staff_user.to_s,
            actor_id:                  User.staff_user.id,
            business:                  @business.slug,
            business_id:               @business.id,
          }

          assert event = events.pop, "a staff.mark_not_spammy event was expected"
          assert_equal "staff.mark_not_spammy", event.name
          assert_equal expected_payload, event.payload
        end
      end

      test "publishes an abuse classification Hydro event" do
        now = Time.parse("2018-01-01")

        Timecop.freeze(now) do
          analyst = create :user, login: "triage-worker"

          @business.mark_as_spammy(reason: "sketchy")
          @business.mark_not_spammy(actor: analyst)

          message = {
            request_context: nil,
            actor: Hydro::EntitySerializer.user(analyst),
            business: Hydro::EntitySerializer.business(@business),
            previous_classification: :SPAMMY,
            current_classification: :NONE,
            previous_spammy_reason: { value: "sketchy" },
            current_spammy_reason: { value: "" },
            previously_suspended: { value: false },
            currently_suspended: { value: false },
            currently_deleted: { value: false },
            origin: :DOTCOM,
            queue_action: :QUEUE_ACTION_NONE,
            queue_entry: nil,
            previous_queue: nil,
            current_queue: nil,
            queued_time_in_seconds: nil,
          }

          assert_hydro_published message, schema: "github.v1.EnterpriseAbuseClassification"
          assert_hydro_messages count: 2, schema: "github.v1.EnterpriseAbuseClassification"
          assert_equal 1, GitHub.dogstats.increments("business.mark_not_spammy").length
        end
      end

      test "publishes an abuse classification Hydro event for hammy classifications" do
        now = Time.parse("2018-01-01")

        Timecop.freeze(now) do
          analyst = create :user, login: "triage-worker"

          @business.mark_as_spammy(reason: "sketchy")
          @business.mark_not_spammy(actor: analyst, whitelist: true)

          message = {
            request_context: nil,
            actor: Hydro::EntitySerializer.user(analyst),
            business: Hydro::EntitySerializer.business(@business),
            previous_classification: :SPAMMY,
            current_classification: :HAMMY,
            previous_spammy_reason: { value: "sketchy" },
            current_spammy_reason: { value: "Not spammy" },
            previously_suspended: { value: false },
            currently_suspended: { value: false },
            currently_deleted: { value: false },
            origin: :DOTCOM,
            queue_action: :QUEUE_ACTION_NONE,
            queue_entry: nil,
            previous_queue: nil,
            current_queue: nil,
            queued_time_in_seconds: nil,
          }

          assert_hydro_published message, schema: "github.v1.EnterpriseAbuseClassification"
          assert_hydro_messages count: 2, schema: "github.v1.EnterpriseAbuseClassification"
        end
      end
    end

    context "#hydro_spammy_and_suspended_data" do
      test "returns a hash of Hydro data containing spammy and suspended statuses of the Business" do
        spammy_classification = Hydro::EntitySerializer.account_spammy_classification(@business)
        spammy_reason = Hydro::EntitySerializer.account_spammy_reason(@business)
        suspended_status = Hydro::EntitySerializer.account_suspended(@business)

        result = @business.hydro_spammy_and_suspended_data

        assert_same_elements %i(
          serialized_previous_classification
          serialized_previous_spammy_reason
          serialized_previously_suspended
        ), result.keys
        assert_equal spammy_classification, result[:serialized_previous_classification]
        assert_equal spammy_reason, result[:serialized_previous_spammy_reason]
        assert_equal suspended_status, result[:serialized_previously_suspended]
      end
    end

    context "#instrument_abuse_classification_publish" do
      test "publishes a Hydro event with given data overriding some defaults" do
        actor = create :user
        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(actor),
          business: Hydro::EntitySerializer.business(@business),
          previous_classification: :NONE,
          current_classification: :NONE,
          previous_spammy_reason: { value: "" },
          current_spammy_reason: { value: "" },
          previously_suspended: { value: false },
          currently_suspended: { value: false },
          currently_deleted: { value: false },
          origin: :DOTCOM,
          queue_action: :QUEUE_ACTION_NONE,
          queue_entry: nil,
          previous_queue: nil,
          current_queue: nil,
          queued_time_in_seconds: nil,
        }

        @business.instrument_abuse_classification_publish(actor: actor)

        assert_hydro_published message, schema: "github.v1.EnterpriseAbuseClassification"
        assert_hydro_messages count: 1, schema: "github.v1.EnterpriseAbuseClassification"
      end
    end

    context "spammy notice" do
      test "is set when Business is spammy" do
        perform_enqueued_jobs only: SpammyBusinessCheckJob do
          @business.update! spammy: true
        end

        assert_equal :spammy_businesses, GlobalNoticeNext.new(viewer: @owner_one).current_notice_name
        assert_equal :spammy_businesses, GlobalNoticeNext.new(viewer: @owner_two).current_notice_name
        refute_equal :spammy_businesses, GlobalNoticeNext.new(viewer: @rando).current_notice_name
      end

      test "is not set when Business is not spammy" do
        assert_enqueued_jobs 0, only: SpammyBusinessCheckJob do
          @business.update! spammy: false
        end

        refute_equal :spammy_businesses, GlobalNoticeNext.new(viewer: @owner_one).current_notice_name
        refute_equal :spammy_businesses, GlobalNoticeNext.new(viewer: @owner_two).current_notice_name
        refute_equal :spammy_businesses, GlobalNoticeNext.new(viewer: @rando).current_notice_name
      end
    end

    context "#check_for_spam" do
      test "does not mark Business as spammy if not considered spammy" do
        @business.check_for_spam

        refute_predicate @business, :spammy?
      end

      test "adds Business to possible spammer queue when appropriate without flagging Business" do
        org_login = "naughtyorg3133t"
        Spam.mark_login_tainted(org_login)
        spammy_org = create :organization, login: org_login
        @business.add_organization(spammy_org)

        GlobalInstrumenter.expects(:instrument).with(
          "add_account_to_spamurai_queue",
          {
            account_global_relay_id: @business.global_relay_id,
            additional_context: "Enterprise account member org spam (login was on tainted list; previous User id: 1)",
            queue_global_relay_id: SpamQueue::SUSPICIOUS_OLDER_ACCOUNTS_GLOBAL_RELAY_ID,
            origin: :DOTCOM,
          },
        )
        @business.check_for_spam

        refute_predicate @business.reload, :spammy?
      end

      test "flags Business as spammy when appropriate" do
        org_login = "naughtyorg3133t"
        Spam.mark_login_tainted(org_login)
        spammy_org = create :organization, login: org_login
        @business.add_organization(spammy_org)

        GitHub::SpamChecker.stubs(:old_or_active?).with(@business).returns(false)
        @business.check_for_spam

        assert_predicate @business.reload, :spammy?
      end
    end
  end
end
