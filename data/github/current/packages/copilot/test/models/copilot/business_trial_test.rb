# typed: strict
# frozen_string_literal: true

require "test_helper"

class BusinessTrialTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include HydroTestHelpers

  sig { params(business_trial: Copilot::BusinessTrial, symbols: T::Array[Symbol]).void }
  def assert_validation_errors(business_trial, symbols)
    symbols.each do |attribute|
      assert business_trial.errors.key?(attribute)
    end
  end

  sig { params(business_trial: Copilot::BusinessTrial, symbols: T::Array[Symbol]).void }
  def refute_validation_errors(business_trial, symbols)
    symbols.each do |attribute|
      refute business_trial.errors.key?(attribute)
    end
  end

  fixtures do
    @enterprise_linked_org = T.let(create(:organization, :enterprise_linked), T.nilable(Organization))
  end

  setup do
    @mailer = T.let(mock, T.nilable(Mocha::Mock))
    T.must(@mailer).stubs(:deliver_later)
    @trial = T.let(create(:copilot_business_trial, :organization, state: "pending", ends_at: 20.days.from_now), T.nilable(Copilot::BusinessTrial))
  end

  context "validations" do
    test "presence of attributes" do
      Copilot::BusinessTrial.destroy_all
      assert_equal 0, Copilot::BusinessTrial.count

      business_trial = Copilot::BusinessTrial.new

      refute business_trial.valid?
      assert_validation_errors(business_trial, %i[ends_at managing_user started_at trialable])

      business_trial.ends_at = Date.current + 1.day
      refute business_trial.valid?
      assert_validation_errors(business_trial, %i[managing_user started_at trialable])
      refute_validation_errors(business_trial, %i[ends_at])

      business_trial.managing_user_id = create(:user).id
      refute business_trial.valid?

      refute business_trial.valid?
      assert_validation_errors(business_trial, %i[started_at trialable])
      refute_validation_errors(business_trial, %i[ends_at managing_user])

      business_trial.started_at = Date.current - 10.days
      refute business_trial.valid?
      assert_validation_errors(business_trial, %i[trialable])
      refute_validation_errors(business_trial, %i[ends_at managing_user started_at])

      business_trial.trialable_type = "Organization"
      business_trial.trialable_id = create(:organization).id
      assert business_trial.valid?

      business_trial.save!

      assert_equal 1, Copilot::BusinessTrial.count
    end

    test "ends at is after started at" do
      business_trial = Copilot::BusinessTrial.new(
        managing_user: build(:user),
        started_at: Date.current,
        trial_length: 1,
        trialable: build(:organization)
      )

      business_trial.ends_at = Date.current - 1.day
      refute business_trial.valid?
      refute_nil business_trial.errors[:ends_at]

      business_trial.ends_at = Date.current
      assert business_trial.valid?

      business_trial.ends_at = Date.current + 10.days
      assert business_trial.valid?
    end

    test "trialable must be an organization" do
      business_trial = Copilot::BusinessTrial.new(
        managing_user: build(:user),
        started_at: Date.current,
        ends_at: Date.current + 1.day,
        trial_length: 1,
        trialable: build(:user)
      )

      refute business_trial.valid?
      assert_equal "must be an Organization", business_trial.errors[:trialable].first

      business_trial.trialable = build(:organization)
      assert business_trial.valid?
    end

    test "trialable must be unique" do
      existing_trial = create(:copilot_business_trial, :organization)

      business_trial = Copilot::BusinessTrial.new(
        managing_user: existing_trial.managing_user,
        started_at: Date.current,
        ends_at: Date.current + 1.day,
        trial_length: 1,
        trialable: existing_trial.trialable,
      )

      refute business_trial.valid?
      assert_equal "has already been taken", business_trial.errors[:trialable].first

      business_trial.trialable = build(:organization)
      assert business_trial.valid?
    end

    context "Copilot Enterprise trials" do
      test "trialable must not be standalone org" do
        standalone_org = build(:business_organization)

        business_trial = Copilot::BusinessTrial.new(
          managing_user: build(:user),
          started_at: Date.current,
          ends_at: Date.current + 1.day,
          trial_length: 1,
          trialable: standalone_org,
          copilot_plan: "enterprise",
        )
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        refute business_trial.valid?
        assert_equal "must not be a standalone Organization", business_trial.errors[:trialable].first

        business_trial.trialable = build(:organization, :enterprise_linked)
        assert business_trial.valid?
      end

      test "trialable's business must not already be on Copilot Enterprise" do
        enterprise_org = build(:organization, :enterprise_linked)
        business = enterprise_org.business
        copilot_business = Copilot::Business.new(business)

        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        copilot_business.copilot_plan_enterprise!

        business_trial = Copilot::BusinessTrial.new(
          managing_user: build(:user),
          started_at: Date.current,
          ends_at: Date.current + 1.day,
          trial_length: 1,
          trialable: enterprise_org,
          copilot_plan: "enterprise",
        )

        refute business_trial.valid?
        assert_equal "business is already on Copilot Enterprise", business_trial.errors[:trialable].first

        copilot_business.copilot_plan_business!
        assert business_trial.valid?
      end

      test "trialable's business must not already be on Copilot Enterprise beta waitlist" do
        enterprise_org = build(:organization, :enterprise_linked)
        business = enterprise_org.business
        enable_feature_flag(:copilot_for_enterprise, business)

        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        business_trial = Copilot::BusinessTrial.new(
          managing_user: build(:user),
          started_at: Date.current,
          ends_at: Date.current + 1.day,
          trial_length: 1,
          trialable: enterprise_org,
          copilot_plan: "enterprise",
        )

        refute business_trial.valid?
        assert_equal "business is already on Copilot Enterprise", business_trial.errors[:trialable].first

        disable_feature_flag(:copilot_for_enterprise, business)
        assert business_trial.valid?
      end

      test "trialable must be Copilot billable" do
        enterprise_org = build(:organization, :enterprise_linked)

        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(false)

        business_trial = Copilot::BusinessTrial.new(
          managing_user: build(:user),
          started_at: Date.current,
          ends_at: Date.current + 1.day,
          trial_length: 1,
          trialable: enterprise_org,
          copilot_plan: "enterprise",
        )

        refute business_trial.valid?
        assert_equal "must be Copilot billable", business_trial.errors[:trialable].first

        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        assert business_trial.valid?
      end
    end
  end

  context ".existing_trial_in_org_has_different_plan?" do
    test "returns false for standalone business", skip_with_all_emus: true do
      org = create(:organization)
      refute Copilot::BusinessTrial.existing_trial_in_org_has_different_plan?(org, "enterprise")
    end

    test "returns false if no other ongoing trial in business" do
      org = create(:organization, :enterprise_linked)
      refute Copilot::BusinessTrial.existing_trial_in_org_has_different_plan?(org, "enterprise")
    end

    test "returns false if expired trial in business is of different type" do
      org = create(:organization, :enterprise_linked)
      other_org = create(:organization, business: org.business)
      create(:copilot_business_trial, :organization, :expired, trialable: other_org, copilot_plan: "business")
      org.business.reload

      refute Copilot::BusinessTrial.existing_trial_in_org_has_different_plan?(org, "enterprise")
    end

    test "returns whether other ongoing trial in org is of different type" do
      org = create(:organization, :enterprise_linked)
      other_org = create(:organization, business: org.business)
      create(:copilot_business_trial, :organization, trialable: other_org, copilot_plan: "business")
      org.business.reload

      refute Copilot::BusinessTrial.existing_trial_in_org_has_different_plan?(org, "business")
      assert Copilot::BusinessTrial.existing_trial_in_org_has_different_plan?(org, "enterprise")
    end
  end

  context ".create_trial!" do
    test "copilot_business plan by default" do
      org = create(:business_organization)
      business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first)

      assert business_trial.copilot_plan_business?
    end

    test "can be copilot_enterprise plan for non-standalone org" do
      org = create(:organization, :enterprise_linked)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first, copilot_plan: "enterprise")

      assert business_trial.copilot_plan_enterprise?
    end

    test "invalid plan" do
      org = create(:business_organization)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      assert_raises_with_message ArgumentError, "'nonsense' is not a valid copilot_plan" do
        Copilot::BusinessTrial.create_trial!(org, org.admins.first, copilot_plan: "nonsense")
      end
    end

    test "does not start the trial instantly if no seats are assigned and the organization is not part of an enterprise trial account" do
      business = create(:business)
      org = create(:organization, business: business)
      business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first)

      refute_predicate business, :trial?
      assert business_trial.copilot_plan_business?
      assert_equal "pending", business_trial.reload.state
    end

    test "starts the trial instantly if the organization is owned by an enterprise trial account" do
      business = create(:business)
      business.update!(trial_expires_at: 30.days.from_now)
      org = create(:organization, business: business)
      business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first)

      assert_predicate business, :trial?
      assert business_trial.copilot_plan_business?
      assert_equal "recently_started", business_trial.reload.state
    end
  end

  context "#start_trial!" do
    test "sets started_at to now, ends_at to now + trial_length, and state to recently_started" do
      freeze_time do
        trial = create(:copilot_business_trial,
                       :organization,
                       started_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       ends_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       trial_length: 10)
        trial.start_trial!

        assert_equal Date.current, trial.started_at
        assert_equal Date.current + 10.days, trial.ends_at
        assert trial.recently_started?
      end
    end

    test "does not enable Copilot if the assigned organization is not owned by a trial enterprise account" do
      freeze_time do
        organization = create(:organization)
        business_trial = Copilot::BusinessTrial.create_trial!(organization.reload, organization.admins.first, trial_length: 30)
        business_trial.start_trial!

        assert business_trial.recently_started?
        refute_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?
      end
    end

    test "enables Copilot if the assigned organization is owned by a trial enterprise account" do
      freeze_time do
        organization = create(:organization)
        create(:business, :metered_ghec, trial_expires_at: 30.days.from_now, dfd_trial: true, organizations: [organization])
        business_trial = Copilot::BusinessTrial.create_trial!(organization.reload, organization.admins.first, trial_length: 30)
        business_trial.start_trial!

        assert business_trial.recently_started?
        assert_predicate Copilot::Organization.new(organization.reload), :copilot_enabled?
      end
    end
  end

  context "#extend_trial!" do
    test "extends the trial before it has been started" do
      freeze_time do
        trial = create(:copilot_business_trial,
                       :organization,
                       started_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       ends_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       trial_length: 10)

        staff_user = create(:user)
        extra_trial_length = 100
        trial.extend_trial!(staff_user, extra_trial_length)

        assert_equal Copilot::BusinessTrial::INACTIVE_DATE, trial.ends_at
        assert_equal 110, trial.trial_length
      end
    end

    test "extends the trial after it has started" do
      freeze_time do
        trial = create(:copilot_business_trial,
                       :organization,
                       started_at: Date.current,
                       ends_at: Date.current + 10.days,
                       trial_length: 10)

        staff_user = create(:user)
        extra_trial_length = 100
        trial.extend_trial!(staff_user, extra_trial_length)

        assert_equal Date.current + 110.days, trial.ends_at
        assert_equal 110, trial.trial_length
      end
    end

    test "extends the trial after it has ended" do
      freeze_time do
        trial = create(:copilot_business_trial,
                       :organization,
                       :expired,
                       trial_length: 30)

        staff_user = create(:user)
        extra_trial_length = 30
        trial.extend_trial!(staff_user, extra_trial_length)

        assert_equal Date.current + (extra_trial_length).days, trial.ends_at
        assert_equal 60, trial.trial_length
      end
    end
  end

  context "#convert_trial!" do
    test "sets started_at, ends_at, trial_length, state and copilot_plan" do
      freeze_time do
        trialable = create(:organization, :enterprise_linked)
        trial = create(:copilot_business_trial, :upgraded, :organization, trialable: trialable)
        staff_user = create(:user)
        new_trial_length = 20

        trial.convert_trial!(staff_user, new_trial_length: new_trial_length, new_copilot_plan: "enterprise")

        trial.reload
        assert_equal Copilot::BusinessTrial::INACTIVE_DATE, trial.started_at
        assert_equal Copilot::BusinessTrial::INACTIVE_DATE, trial.ends_at
        assert_equal new_trial_length, trial.trial_length
        assert trial.pending?
        assert trial.copilot_plan_enterprise?
      end
    end

    test "sets trialable's business copilot_for_dotcom policy to No policy if unconfigured" do
      trialable = create(:organization, :enterprise_linked)
      trial = create(:copilot_business_trial, :upgraded, :organization, trialable: trialable)
      staff_user = create(:user)
      new_trial_length = 20

      refute Copilot::Business.new(trialable.business).copilot_for_dotcom_unconfigured? # instantiate the config

      Copilot::Configuration.where(configurable_type: "business", configurable_id: trialable.business.id).take&.update!(
        dotcom_chat: :unconfigured,
        github_enterprise_feature_group: :unconfigured,
        pr_summarizations: :unconfigured
      )

      assert Copilot::Business.new(trialable.business).copilot_for_dotcom_unconfigured?

      trial.convert_trial!(staff_user, new_trial_length: new_trial_length, new_copilot_plan: "enterprise")

      assert Copilot::Business.new(trialable.business).copilot_for_dotcom_no_policy?
    end

    test "Sets trialable's business copilot_for_dotcom policy to No policy if disabled" do
      trialable = create(:organization, :enterprise_linked)
      trial = create(:copilot_business_trial, :upgraded, :organization, trialable: trialable)
      staff_user = create(:user)
      new_trial_length = 20

      Copilot::Business.new(trialable.business).copilot_for_dotcom_disabled!

      trial.convert_trial!(staff_user, new_trial_length: new_trial_length, new_copilot_plan: "enterprise")

      assert Copilot::Business.new(trialable.business).copilot_for_dotcom_no_policy?
    end

    test "keeps trialable's business copilot_for_dotcom policy to Enabled if enabled" do
      trialable = create(:organization, :enterprise_linked)
      trial = create(:copilot_business_trial, :upgraded, :organization, trialable: trialable)
      staff_user = create(:user)
      new_trial_length = 20

      trial.convert_trial!(staff_user, new_trial_length: new_trial_length, new_copilot_plan: "enterprise")

      assert Copilot::Business.new(trialable.business).copilot_for_dotcom_enabled?
    end

    test "logs the relevant info" do
      freeze_time do
        organization = create(:organization, :enterprise_linked)
        trial = create(:copilot_business_trial, :upgraded, :organization, trialable: organization)
        previous_ends_at = trial.ends_at
        previous_copilot_plan = trial.copilot_plan

        staff_user = create(:user)
        new_trial_length = 20

        logs = capture_logs do
          trial.convert_trial!(staff_user, new_trial_length: new_trial_length, new_copilot_plan: "enterprise")
        end

        assert_log_match logs, "gh.copilot.business_trial.previous_copilot_plan", "business"
        assert_log_match logs, "gh.copilot.business_trial.new_copilot_plan", "enterprise"
        assert_log_match logs, "gh.copilot.business_trial.previous_state", "upgraded"
        assert_log_match logs, "gh.copilot.business_trial.new_state", "pending"
        assert_log_match logs, "gh.copilot.business_trial.converted_by", staff_user.display_login

        trial.reload

        assert_hydro_published(
          {
            staff_actor: Hydro::EntitySerializer.user(staff_user),
            organization: Hydro::EntitySerializer.organization(organization),
            business: Hydro::EntitySerializer.business(organization.business),
            previous_trial_ends_at: Google::Protobuf::Timestamp.new(seconds: previous_ends_at.to_i, nanos: 0),
            updated_trial_ends_at: Google::Protobuf::Timestamp.new(seconds: trial.ends_at.to_i, nanos: 0),
            reason: "Trial converted to enterprise plan",
            old_copilot_plan: Hydro::EntitySerializer.copilot_plan(previous_copilot_plan),
            new_copilot_plan: Hydro::EntitySerializer.copilot_plan(trial.copilot_plan),
          },
          schema: "github.copilot.v2.CopilotForBusinessTrialChanged"
        )
      end
    end

    test "raises an error if trialable is standalone" do
      freeze_time do
        org = create(:business_organization)
        trial = Copilot::BusinessTrial.new(state: :upgraded, trialable: org)
        staff_user = create(:user)
        new_trial_length = 20

        assert_raises ActiveRecord::RecordInvalid do
          trial.convert_trial!(staff_user, new_trial_length: new_trial_length, new_copilot_plan: "enterprise")
        end
      end
    end
  end

  context "#upgrade!" do
    test "sets started_at to now, ends_at to now to now, and state to upgraded when trial has started" do
      freeze_time do
        trial = create(:copilot_business_trial,
                       :organization,
                       started_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       ends_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       trial_length: 10)
        trial.start_trial!
        trial.stubs(:upgradable?).returns(true)

        assert_enqueued_jobs(1, only: Copilot::BusinessTrials::UpgradeCleanupJob) do
          trial.upgrade!(create(:user))
        end

        assert_equal Date.current, trial.started_at
        assert_equal Date.current, trial.ends_at
        assert trial.upgraded?
      end
    end

    test "sets started_at to now, ends_at to now to now, and state to upgraded when trial has not started" do
      freeze_time do
        trial = create(:copilot_business_trial,
                       :organization,
                       started_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       ends_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       trial_length: 10)
        trial.stubs(:upgradable?).returns(true)

        assert_enqueued_jobs(1, only: Copilot::BusinessTrials::UpgradeCleanupJob) do
          trial.upgrade!(create(:user))
        end

        assert_equal Date.current, trial.started_at
        assert_equal Date.current, trial.ends_at
        assert trial.upgraded?
      end
    end

    test "throws an error when the trial is not upgradable" do
      freeze_time do
        trial = create(:copilot_business_trial,
                       :organization,
                       started_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       ends_at: Copilot::BusinessTrial::INACTIVE_DATE,
                       trial_length: 10)
        trial.stubs(:upgradable?).returns(false)

        assert_raises Copilot::Errors::OrgTrialUpgradeError do
          trial.upgrade!(create(:user))
        end

        refute trial.upgraded?
      end
    end

    test "does not run UpgradeCleanupJob for Copilot Enterprise trial" do
      copilot_seat = create(:copilot_seat)
      organization = copilot_seat.organization
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      trial = create(:copilot_business_trial,
        trialable: organization,
        copilot_plan: "enterprise",
      )
      trial.stubs(:upgradable?).returns(true)

      assert_enqueued_jobs(0, only: Copilot::BusinessTrials::UpgradeCleanupJob) do
        trial.upgrade!(create(:user))
      end

      assert trial.upgraded?
    end
  end

  context "#restart!" do
    test "updates ends_at and restores the state to :recently_started" do
      trial = create(:copilot_business_trial, :organization, state: :canceled, ends_at: Date.current)

      logs = capture_logs do
        trial.restart!
      end

      assert_match "Restarting trial", logs
      assert_match "gh.copilot.business_trial.id=\"#{trial.id}", logs
      assert_match "gh.copilot.business_trial.previous_state=\"canceled", logs

      trial.reload
      assert_equal "recently_started", trial.state
      assert_equal Date.current + 30.days, trial.ends_at
    end

    test "does nothing if the trial is not in a cancelled state" do
      trial = create(:copilot_business_trial, :organization, state: :recently_started)

      logs = capture_logs do
        trial.restart!
      end

      assert_equal "", logs

      trial.reload
      assert_equal "recently_started", trial.state
    end

    test "updates the trial length to match the parent enterprise account's trial expiration date" do
      business = create(:business)
      business.update!(trial_expires_at: 25.days.from_now.to_time)
      org = create(:organization)

      business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first, trial_length: 30)
      business_trial.start_trial!
      business.add_organization(org)
      assert_equal 30, business_trial.trial_length
      assert_equal Date.current + 30.days, business_trial.ends_at

      business_trial.cancel!
      assert_equal business_trial.reload.state, "canceled"

      # When restarted, will have the trial length of the parent enterprise account
      business_trial.restart!
      assert_equal "recently_started", business_trial.reload.state
      assert_equal business.trial_days_remaining, business_trial.trial_length
      assert_equal business.trial_expires_at, business_trial.ends_at  # Has the same end time as the parent enterprise account's trial
    end
  end

  context "#cancel!" do
    test "cancels seats and assignments when canceling a Copilot Business trial" do
      trial = create(:copilot_business_trial, :organization, state: :pending)

      CopilotForBusinessMailer.expects(:trial_half_over).never
      CopilotForBusinessMailer.expects(:trial_nearly_over).never
      CopilotForBusinessMailer.expects(:trial_final_day).never
      Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).with(trial.trialable.id).once

      ass = create(:copilot_seat_assignment, :organization, organization: trial.trialable)
      ass.convert_to_seats
      seats = ass.seats

      logs = capture_logs do
        trial.cancel!
      end

      assert_match "Canceling trial", logs
      assert_match "gh.copilot.business_trial.id=\"#{trial.id}", logs
      assert_match "gh.copilot.business_trial.previous_state=\"pending", logs

      trial.reload
      assert_equal "canceled", trial.state

      refute Copilot::SeatAssignment.find_by(id: ass.id)
      seats.each do |seat|
        refute Copilot::Seat.find_by(id: seat.id)
      end
    end

    test "does not cancel seats and assignments when canceling a Copilot Enterprise trial" do
      organization = create(:organization, :enterprise_linked)
      staff = create(:staff_admin_user)

      # Some set up to ensure that the Copilot Enterprise trial can be created and then started
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Organization.new(organization).copilot_for_dotcom_enabled!

      trial = Copilot::BusinessTrial.create_trial!(organization, staff, copilot_plan: "enterprise")

      CopilotEnterpriseMailer.expects(:trial_half_over).never
      CopilotEnterpriseMailer.expects(:trial_nearly_over).never
      CopilotEnterpriseMailer.expects(:trial_final_day).never
      Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).with(trial.trialable.id).once

      seat_assignments = create(:copilot_seat_assignment, :organization, organization: trial.trialable)
      seat_assignments.convert_to_seats
      seats = seat_assignments.seats

      trial.reload

      logs = capture_logs do
        trial.cancel!
      end

      assert_match "Canceling trial", logs
      assert_match "gh.copilot.business_trial.id=\"#{trial.id}", logs
      assert_match "gh.copilot.business_trial.previous_state=\"recently_started", logs

      trial.reload

      assert_equal "canceled", trial.state

      assert Copilot::SeatAssignment.find_by(id: seat_assignments.id)
      seats.each do |seat|
        assert Copilot::Seat.find_by(id: seat.id)
      end
    end

    test "updates the ends_at and state" do
      trial = create(:copilot_business_trial, :organization, state: :pending)

      CopilotForBusinessMailer.expects(:trial_half_over).never
      CopilotForBusinessMailer.expects(:trial_nearly_over).never
      CopilotForBusinessMailer.expects(:trial_final_day).never
      Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).with(trial.trialable.id).once

      logs = capture_logs do
        trial.cancel!
      end

      assert_match "Canceling trial", logs
      assert_match "gh.copilot.business_trial.id=\"#{trial.id}", logs
      assert_match "gh.copilot.business_trial.previous_state=\"pending", logs

      trial.reload
      assert_equal "canceled", trial.state
      assert_equal Date.current, trial.ends_at
    end

    test "does not cancel Copilot if the assigned organization is not owned by a trial enterprise account" do
      organization = create(:organization)
      business_trial = Copilot::BusinessTrial.create_trial!(organization.reload, organization.admins.first, trial_length: 30)
      business_trial.start_trial!
      Copilot::Organization.new(organization).enable_copilot!

      assert business_trial.recently_started?
      assert_predicate Copilot::Organization.new(organization), :copilot_enabled?

      business_trial.cancel!

      assert_equal "canceled", business_trial.reload.state
      assert_predicate Copilot::Organization.new(organization), :copilot_enabled?
    end

    test "cancels Copilot if the assigned organization is owned by a trial enterprise account" do
      organization = create(:organization)
      create(:business, :metered_ghec, trial_expires_at: 30.days.from_now, dfd_trial: true, organizations: [organization])
      business_trial = Copilot::BusinessTrial.create_trial!(organization.reload, organization.admins.first, trial_length: 30)
      business_trial.start_trial!
      Copilot::Organization.new(organization).enable_copilot!

      assert business_trial.recently_started?
      assert_predicate Copilot::Organization.new(organization), :copilot_enabled?

      business_trial.cancel!

      assert_equal "canceled", business_trial.reload.state
      refute_predicate Copilot::Organization.new(organization), :copilot_enabled?
    end
  end

  context "#active?" do
    test "returns true if the state is in ACTIVE_STATES" do
      Copilot::BusinessTrial::ACTIVE_STATES.each do |state|
        assert Copilot::BusinessTrial.new(state: state).active?
      end
    end

    test "returns false if the state is not in ACTIVE_STATES" do
      (Copilot::BusinessTrial.states.keys - Copilot::BusinessTrial::ACTIVE_STATES).each do |state|
        refute Copilot::BusinessTrial.new(state: state).active?
      end
    end
  end

  context "#update_expiration!" do
    test "syncs when in the future" do
      freeze_time do
        trial = create(:copilot_business_trial, :organization, state: :pending, ends_at: Date.current)
        new_date = (trial.ends_at + 10.days)

        logs = capture_logs do
          trial.update_expiration!(new_date)
        end
        assert_match "Syncing trial to organization or business", logs
        assert_equal new_date, trial.reload.ends_at
      end
    end

    test "cancels when in the past" do
      freeze_time do
        trial = create(:copilot_business_trial, :organization, state: :pending, ends_at: Date.current)
        new_date = (trial.ends_at - 10.days)

        logs = capture_logs do
          trial.update_expiration!(new_date)
        end
        assert_match "Not syncing because expires_at is in past", logs
        assert_equal "canceled", trial.reload.state
      end
    end
  end

  context "#started?" do
    test "true when the started_at date is not the INACTIVE_DATE" do
      trial = Copilot::BusinessTrial.new(started_at: Date.current, state: :recently_started)
      assert trial.started?
    end

    test "false when the started_at date is the INACTIVE_DATE" do
      trial = Copilot::BusinessTrial.new(started_at: Copilot::BusinessTrial::INACTIVE_DATE)
      refute trial.started?
    end

    test "false when the state isn't one of them shiny ACTIVE states" do
      trial = create(:copilot_business_trial, :organization, started_at: Date.current, state: :pending)
      refute trial.started?

      trial.update!(state: :expired)
      refute trial.started?

      trial.update!(state: :canceled)
      refute trial.started?
    end
  end

  context "#has_trial?" do
    test "returns false if trial ended" do
      business_trial = Copilot::BusinessTrial.new(ends_at: Date.current - 1.day)
      refute business_trial.has_trial?
    end

    test "returns true if trial has not yet ended" do
      business_trial = Copilot::BusinessTrial.new(ends_at: 30.days.from_now)
      assert business_trial.has_trial?
    end
  end

  context "#days_left" do
    test "returns the number of days left in the trial" do
      business_trial = Copilot::BusinessTrial.new(ends_at: Date.current + 10.days)
      assert_equal 10, business_trial.days_left
    end

    test "returns 0 if the trial has ended" do
      business_trial = Copilot::BusinessTrial.new(ends_at: Date.current - 1.day)
      assert_equal 0, business_trial.days_left
    end

    test "returns a maximum of 999 days" do
      business_trial = Copilot::BusinessTrial.new(ends_at: Date.current + 2000.days)
      assert_equal 999, business_trial.days_left
    end
  end

  context "#upgradable?" do
    context "when copilot_plan_business?" do
      test "returns true if the trial is not expired, not upgraded, and the org is billable" do
        org = build(:organization)
        business_trial = Copilot::BusinessTrial.new(state: :pending, trialable: org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        assert business_trial.upgradable?
      end

      test "returns false if the trial is cancelled" do
        org = build(:organization)
        business_trial = Copilot::BusinessTrial.new(state: :canceled, trialable: org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        refute business_trial.upgradable?
      end

      test "returns false if the trial is expired" do
        org = build(:organization)
        business_trial = Copilot::BusinessTrial.new(state: :expired, trialable: org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        refute business_trial.upgradable?
      end

      test "returns false if the trial is upgraded" do
        org = build(:organization)
        business_trial = Copilot::BusinessTrial.new(state: :upgraded, trialable: org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        refute business_trial.upgradable?
      end

      test "returns false if the org is not billable" do
        org = build(:organization)
        business_trial = Copilot::BusinessTrial.new(state: :pending, trialable: org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(false)
        refute business_trial.upgradable?
      end
    end

    context "when copilot_plan_enterprise?" do
      test "returns true if the trial is in good state, the org is billable, org has Copilot seats, and is not standalone" do
        enterprise_trial = Copilot::BusinessTrial.new(state: :pending, trialable: @enterprise_linked_org, copilot_plan: "enterprise")
        create(:copilot_seat, organization: @enterprise_linked_org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        assert enterprise_trial.upgradable?
      end

      test "returns false if trial is cancelled" do
        enterprise_trial = Copilot::BusinessTrial.new(state: :canceled, trialable: @enterprise_linked_org, copilot_plan: "enterprise")
        create(:copilot_seat, organization: @enterprise_linked_org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        refute enterprise_trial.upgradable?
      end

      test "returns false if the trial is expired" do
        enterprise_trial = Copilot::BusinessTrial.new(state: :expired, trialable: @enterprise_linked_org, copilot_plan: "enterprise")
        create(:copilot_seat, organization: @enterprise_linked_org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        refute enterprise_trial.upgradable?
      end

      test "returns false if trial is upgraded" do
        enterprise_trial = Copilot::BusinessTrial.new(state: :upgraded, trialable: @enterprise_linked_org, copilot_plan: "enterprise")
        create(:copilot_seat, organization: @enterprise_linked_org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        refute enterprise_trial.upgradable?
      end

      test "returns false if the org is not billable" do
        enterprise_trial = Copilot::BusinessTrial.new(state: :pending, trialable: @enterprise_linked_org, copilot_plan: "enterprise")
        create(:copilot_seat, organization: @enterprise_linked_org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(false)

        refute enterprise_trial.upgradable?
      end

      test "returns false if the org is standalone" do
        standalone_org = create(:organization)
        enterprise_trial = Copilot::BusinessTrial.new(state: :pending, trialable: standalone_org, copilot_plan: "enterprise")
        create(:copilot_seat, organization: standalone_org)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        refute enterprise_trial.upgradable?
      end

      test "returns false if there are no Copilot Business seats for the org" do
        enterprise_trial = Copilot::BusinessTrial.new(state: :pending, trialable: @enterprise_linked_org, copilot_plan: "enterprise")
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(false)

        refute enterprise_trial.upgradable?
      end
    end
  end

  context "#belongs_to_trial_business_account" do
    test "returns true if the organization belongs to an enterprise trial account" do
      business = create(:business, trial_expires_at: 30.days.from_now)
      org = create(:organization, business: business)
      business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first)

      refute_nil org.business
      assert_predicate business, :trial?
      assert_predicate business_trial, :belongs_to_trial_business_account?
    end

    test "returns false if the organization belongs to an enterprise account that is not a trial" do
      business = create(:business)
      org = create(:organization, business: business)
      business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first)

      refute_nil org.business
      refute_predicate business, :trial?
      refute_predicate business_trial, :belongs_to_trial_business_account?
    end

    test "returns false if the organization does not belong to an enterprise account" do
      org = create(:organization)
      business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first)

      assert_nil org.business
      refute_predicate business_trial, :belongs_to_trial_business_account?
    end
  end

  context "#startable?" do
    context "Copilot Business trials" do
      test "returns true when pending" do
        trial = create(:copilot_business_trial, :organization, state: "pending")

        assert trial.startable?
      end

      test "returns false when non-pending" do
        trial = create(:copilot_business_trial, :organization, state: "recently_started")

        refute trial.startable?
      end
    end

    context "Copilot Enterprise trials" do
      test "returns true when pending and copilot_for_dotcom is enabled" do
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        organization = create(:organization, :enterprise_linked)
        trial = create(:copilot_business_trial, :organization,
          copilot_plan: "enterprise",
          state: "pending",
          trialable: organization,
        )

        # Doing this instead of calling copilot_org.copilot_for_dotcom_enabled! since that would now trigger starting the CE trial
        create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: organization)

        assert trial.startable?
      end

      test "returns false when pending and copilot_for_dotcom is disabled" do
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        organization = create(:organization, :enterprise_linked)
        trial = create(:copilot_business_trial, :organization,
          copilot_plan: "enterprise",
          state: "pending",
          trialable: organization,
        )

        refute Copilot::Organization.new(organization).copilot_for_dotcom_enabled?
        refute trial.startable?
      end

      test "returns true when pending but skip_copilot_for_dotcom_enabled_check flag is true" do
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        organization = create(:organization, :enterprise_linked)
        trial = create(:copilot_business_trial, :organization,
          copilot_plan: "enterprise",
          state: "pending",
          trialable: organization,
        )

        refute Copilot::Organization.new(organization).copilot_for_dotcom_enabled?
        assert trial.startable?(skip_copilot_for_dotcom_enabled_check: true)
      end

      test "returns false when non-pending" do
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        organization = create(:organization, :enterprise_linked)
        trial = create(:copilot_business_trial, :organization,
          copilot_plan: "enterprise",
          state: "recently_started",
          trialable: organization,
        )

        refute trial.startable?
      end
    end
  end

  context "#can_be_converted_to_copilot_enterprise_trial?" do
    context "Copilot Business trials" do
      test "returns true when upgraded" do
        trial = create(:copilot_business_trial, :organization, state: "upgraded")

        assert trial.can_be_converted_to_copilot_enterprise_trial?
      end

      test "returns true when expired" do
        trial = create(:copilot_business_trial, :organization, state: "expired")

        assert trial.can_be_converted_to_copilot_enterprise_trial?
      end

      test "returns true when canceled" do
        trial = create(:copilot_business_trial, :organization, state: "canceled")

        assert trial.can_be_converted_to_copilot_enterprise_trial?
      end

      test "returns false when pending" do
        trial = create(:copilot_business_trial, :organization, state: "pending")

        refute trial.can_be_converted_to_copilot_enterprise_trial?
      end
    end

    context "Copilot Enterprise trials" do
      test "returns false" do
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        organization = create(:organization, :enterprise_linked)
        trial = create(:copilot_business_trial, :organization,
          copilot_plan: "enterprise",
          state: "pending",
          trialable: organization,
        )

        refute trial.can_be_converted_to_copilot_enterprise_trial?
      end
    end
  end

  context "#notify_admin_of_trial_creation" do
    test "sends email to admin when a Copilot Business trial is created" do
      org = create(:organization)
      CopilotForBusinessMailer.expects(:trial_welcome).with(org, 10).returns(@mailer).once

      create(:copilot_business_trial, trialable: org, state: :pending, trial_length: 10)
    end

    test "sends email to admin when a Copilot Enterprise trial is created" do
      business = create(:business)
      organization = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      CopilotEnterpriseMailer.expects(:trial_welcome).with(organization, 10).returns(@mailer).once

      create(:copilot_business_trial, trialable: organization, state: :pending, trial_length: 10, copilot_plan: "enterprise")
    end
  end

  context "#on_state_change" do
    context "transitioning to half_over" do
      test "sends email when on Copilot Business trial" do
        trial = create(:copilot_business_trial, :organization, state: :pending)

        CopilotForBusinessMailer.expects(:trial_half_over).with(trial.trialable).returns(@mailer).once
        CopilotForBusinessMailer.expects(:trial_nearly_over).never
        CopilotForBusinessMailer.expects(:trial_final_day).never
        CopilotForBusinessMailer.expects(:trial_expired).never
        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).never

        trial.half_over!
      end

      test "sends email when on Copilot Enterprise trial" do
        business = create(:business)
        organization = create(:organization, business: business)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        trial = create(:copilot_business_trial, trialable: organization, state: :pending, copilot_plan: "enterprise")

        CopilotEnterpriseMailer.expects(:trial_half_over).with(trial.trialable).returns(@mailer).once
        CopilotEnterpriseMailer.expects(:trial_nearly_over).never
        CopilotEnterpriseMailer.expects(:trial_final_day).never
        CopilotEnterpriseMailer.expects(:trial_expired).never
        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).never

        trial.half_over!
      end
    end

    context "transitioning to nearly_over" do
      test "sends email when on Copilot Business trial" do
        trial = create(:copilot_business_trial, :organization, state: :pending)

        CopilotForBusinessMailer.expects(:trial_half_over).never
        CopilotForBusinessMailer.expects(:trial_nearly_over).with(trial.trialable).returns(@mailer).once
        CopilotForBusinessMailer.expects(:trial_final_day).never
        CopilotForBusinessMailer.expects(:trial_expired).never
        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).never

        trial.nearly_over!
      end

      test "sends email when on Copilot Enterprise trial" do
        business = create(:business)
        organization = create(:organization, business: business)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        trial = create(:copilot_business_trial, trialable: organization, state: :pending, copilot_plan: "enterprise")

        CopilotEnterpriseMailer.expects(:trial_half_over).never
        CopilotEnterpriseMailer.expects(:trial_nearly_over).with(trial.trialable).returns(@mailer).once
        CopilotEnterpriseMailer.expects(:trial_final_day).never
        CopilotEnterpriseMailer.expects(:trial_expired).never
        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).never

        trial.nearly_over!
      end
    end

    context "transitioning to final_day" do
      test "sends email when on Copilot Business trial" do
        trial = create(:copilot_business_trial, :organization, state: :pending)

        CopilotForBusinessMailer.expects(:trial_half_over).never
        CopilotForBusinessMailer.expects(:trial_nearly_over).never
        CopilotForBusinessMailer.expects(:trial_final_day).with(trial.trialable).returns(@mailer).once
        CopilotForBusinessMailer.expects(:trial_expired).never
        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).never

        trial.final_day!
      end

      test "sends email when on Copilot Enterprise trial" do
        business = create(:business)
        organization = create(:organization, business: business)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        trial = create(:copilot_business_trial, trialable: organization, state: :pending, copilot_plan: "enterprise")

        CopilotEnterpriseMailer.expects(:trial_half_over).never
        CopilotEnterpriseMailer.expects(:trial_nearly_over).never
        CopilotEnterpriseMailer.expects(:trial_final_day).with(trial.trialable).returns(@mailer).once
        CopilotEnterpriseMailer.expects(:trial_expired).never
        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).never

        trial.final_day!
      end
    end

    context "transitioning to expired" do
      test "sends email and kicks off expiration job when on Copilot Business trial" do
        trial = create(:copilot_business_trial, :organization)

        CopilotForBusinessMailer.expects(:trial_half_over).never
        CopilotForBusinessMailer.expects(:trial_nearly_over).never
        CopilotForBusinessMailer.expects(:trial_final_day).never
        CopilotForBusinessMailer.expects(:trial_expired).with(trial.trialable).returns(@mailer).once

        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).with(trial.trialable.id).once

        trial.expired!
      end

      test "sends email and kicks off expiration job when on Copilot Enterprise trial" do
        business = create(:business)
        organization = create(:organization, business: business)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        trial = create(:copilot_business_trial, trialable: organization, copilot_plan: "enterprise")
        seat = create(:copilot_seat, organization: organization)

        CopilotEnterpriseMailer.expects(:trial_half_over).never
        CopilotEnterpriseMailer.expects(:trial_nearly_over).never
        CopilotEnterpriseMailer.expects(:trial_final_day).never
        CopilotEnterpriseMailer.expects(:trial_expired).with(trial.trialable).returns(@mailer).once
        CopilotEnterpriseMailer.expects(:trial_expired_for_user).with(trial.trialable, seat.assigned_user).returns(@mailer).once

        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).with(trial.trialable.id).once

        trial.expired!
      end

      test "does not send email to user when business is already on Copilot Enterprise" do
        business = create(:business)
        organization = create(:organization, business: business)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        trial = create(:copilot_business_trial, trialable: organization, copilot_plan: "enterprise")

        Copilot::Business.new(business).copilot_plan_enterprise!

        CopilotEnterpriseMailer.expects(:trial_expired).with(trial.trialable).returns(@mailer).once
        CopilotEnterpriseMailer.expects(:trial_expired_for_user).never

        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).with(trial.trialable.id).once

        trial.expired!
      end
    end

    context "transitioning to canceled" do
      test "kicks off expiration job when on Copilot Business trial" do
        trial = create(:copilot_business_trial, :organization, state: :pending)

        CopilotForBusinessMailer.expects(:trial_half_over).never
        CopilotForBusinessMailer.expects(:trial_nearly_over).never
        CopilotForBusinessMailer.expects(:trial_final_day).never
        CopilotForBusinessMailer.expects(:trial_expired).never
        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).with(trial.trialable.id).once

        trial.canceled!
      end

      test "kicks off expiration job when on Copilot Enterprise trial" do
        business = create(:business)
        organization = create(:organization, business: business)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        trial = create(:copilot_business_trial, trialable: organization, state: :pending, copilot_plan: "enterprise")

        CopilotEnterpriseMailer.expects(:trial_half_over).never
        CopilotEnterpriseMailer.expects(:trial_nearly_over).never
        CopilotEnterpriseMailer.expects(:trial_final_day).never
        CopilotEnterpriseMailer.expects(:trial_expired).never
        Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).with(trial.trialable.id).once

        trial.canceled!
      end
    end

    test "does not do anything when transitioning to any other state" do
      trial = create(:copilot_business_trial, :organization, state: :pending)

      CopilotForBusinessMailer.expects(:trial_half_over).never
      CopilotForBusinessMailer.expects(:trial_nearly_over).never
      CopilotForBusinessMailer.expects(:trial_final_day).never
      CopilotForBusinessMailer.expects(:trial_expired).never
      CopilotEnterpriseMailer.expects(:trial_half_over).never
      CopilotEnterpriseMailer.expects(:trial_nearly_over).never
      CopilotEnterpriseMailer.expects(:trial_final_day).never
      CopilotEnterpriseMailer.expects(:trial_expired).never
      Copilot::BusinessTrials::ExpirationJob.expects(:perform_later).never

      (Copilot::BusinessTrial.states.keys - %w[recently_started half_over nearly_over final_day expired canceled]).each do |state|
        trial.update!(state: state)
      end
    end
  end

  context "#process_disabling_copilot_enterprise_features" do
    test "disables the Copilot Enterprise features" do
      business = create(:business)
      organization = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      enterprise_trial = Copilot::BusinessTrial.create_trial!(organization, create(:staff_admin_user), copilot_plan: "enterprise")

      assert Copilot::Organization.new(organization).copilot_for_dotcom_unconfigured?

      Copilot::Business.new(business).copilot_for_dotcom_enabled! # Set the Copilot in GitHub.com policy to `enabled`

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?

      assert_logged("Body" => "Disabling Copilot Enterprise features for the business", "gh.business.id" => business.id) do
        perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
          enterprise_trial.process_disabling_copilot_enterprise_features
        end
      end

      assert Copilot::Business.new(business).copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
    end

    test "does not disable the Copilot Enterprise features when the enterprise's copilot plan is already Copilot Enterprise and the Copilot in GitHub.com policy is enabled at the enterprise level" do
      business = create(:business)
      organization = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      enterprise_trial = Copilot::BusinessTrial.create_trial!(organization, create(:staff_admin_user), copilot_plan: "enterprise")

      assert Copilot::Organization.new(organization).copilot_for_dotcom_unconfigured?

      Copilot::Business.new(business).copilot_plan_enterprise! # Update the Copilot plan
      Copilot::Business.new(business).copilot_for_dotcom_enabled! # Set the Copilot Enterprise features to `enabled`

      assert_logged("Body" => "Leaving Copilot Enterprise features for the business and organization as enabled as the business's copilot plan is already enterprise", "gh.business.id" => business.id) do
        enterprise_trial.process_disabling_copilot_enterprise_features
      end
      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
    end

    test "does not disable the Copilot Enterprise features when the enterprise is on the waitlist and the Copilot in GitHub.com policy is enabled at the enterprise level" do
      business = create(:business)
      organization = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      enterprise_trial = Copilot::BusinessTrial.create_trial!(organization, create(:staff_admin_user), copilot_plan: "enterprise")

      enable_feature_flag(:copilot_for_enterprise, business)

      assert Copilot::Organization.new(organization).copilot_for_dotcom_unconfigured?

      Copilot::Business.new(business).copilot_for_dotcom_enabled! # Set the Copilot Enterprise features to `enabled` at the ent level

      assert_logged("Body" => "Leaving Copilot Enterprise features for the business and organization as enabled as the business is on the waitlist feature flag", "gh.business.id" => business.id) do
        enterprise_trial.process_disabling_copilot_enterprise_features
      end

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
    end

    test "disables the Copilot Enterprise features at the org level only when the enterprise's copilot plan is already enterprise" do
      business = create(:business)
      organization = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      enterprise_trial = Copilot::BusinessTrial.create_trial!(organization, create(:staff_admin_user), copilot_plan: "enterprise")

      assert Copilot::Organization.new(organization).copilot_for_dotcom_unconfigured?

      Copilot::Business.new(business).copilot_plan_enterprise! # Update the Copilot plan
      Copilot::Business.new(business).copilot_for_dotcom_no_policy!
      Copilot::Organization.new(organization).copilot_for_dotcom_enabled! # Set the Copilot Enterprise features to `enabled` at the org level

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?

      refute_logged("Body" => "Disabling Copilot Enterprise features for the business", "gh.business.id" => business.id) do
        assert_logged("Body" => "Disabling Copilot Enterprise features for the organization", "gh.org.id" => organization.id) do
          enterprise_trial.process_disabling_copilot_enterprise_features
        end
      end

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
    end

    test "disables the Copilot Enterprise features at the org level only when the enterprise is on the waitlist" do
      business = create(:business)
      organization = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      enterprise_trial = Copilot::BusinessTrial.create_trial!(organization, create(:staff_admin_user), copilot_plan: "enterprise")

      enable_feature_flag(:copilot_for_enterprise, business)

      assert Copilot::Organization.new(organization).copilot_for_dotcom_unconfigured?

      Copilot::Business.new(business).copilot_for_dotcom_no_policy!
      Copilot::Organization.new(organization).copilot_for_dotcom_enabled! # Set the Copilot Enterprise features to `enabled` at the org level

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?

      refute_logged("Body" => "Disabling Copilot Enterprise features for the business", "gh.business.id" => business.id) do
        assert_logged("Body" => "Disabling Copilot Enterprise features for the organization", "gh.org.id" => organization.id) do
          enterprise_trial.process_disabling_copilot_enterprise_features
        end
      end

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
    end

    test "disables the Copilot Enterprise features at the org level only when there is another org on a Copilot Enterprise trial" do
      business = create(:business)
      organization = create(:organization, business: business)
      organization2 = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      enterprise_trial = Copilot::BusinessTrial.create_trial!(organization, create(:staff_admin_user), copilot_plan: "enterprise")
      Copilot::BusinessTrial.create_trial!(organization2, create(:staff_admin_user), copilot_plan: "enterprise")

      assert Copilot::Organization.new(organization).copilot_for_dotcom_unconfigured?
      assert Copilot::Organization.new(organization2).copilot_for_dotcom_unconfigured?

      Copilot::Organization.new(organization).copilot_for_dotcom_enabled! # Set the Copilot Enterprise features to `enabled` at the org level
      Copilot::Organization.new(organization2).copilot_for_dotcom_enabled!

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization2).copilot_for_dotcom_disabled?

      refute_logged("Body" => "Disabling Copilot Enterprise features for the business", "gh.business.id" => business.id) do
        assert_logged("Body" => "Disabling Copilot Enterprise features for the organization", "gh.org.id" => organization.id) do
          enterprise_trial.process_disabling_copilot_enterprise_features
        end
      end

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization2).copilot_for_dotcom_disabled?
    end

    test "disables the Copilot Enterprise features at the org level only if there are orgs on Copilot Enterprise plan under mixed licensing" do
      business = create(:business)
      organization = create(:organization, business: business)
      organization2 = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      enterprise_trial = Copilot::BusinessTrial.create_trial!(organization, create(:staff_admin_user), copilot_plan: "enterprise")
      Copilot::Organization.new(organization2).copilot_plan_enterprise!

      assert Copilot::Organization.new(organization).copilot_for_dotcom_unconfigured?

      Copilot::Organization.new(organization).copilot_for_dotcom_enabled! # Set the Copilot Enterprise features to `enabled` at the org level
      Copilot::Business.new(business).copilot_for_dotcom_enabled!
      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?

      refute_logged("Body" => "Disabling Copilot Enterprise features for the business", "gh.business.id" => business.id) do
        assert_logged("Body" => "Disabling Copilot Enterprise features for the organization", "gh.org.id" => organization.id) do
          enterprise_trial.process_disabling_copilot_enterprise_features
        end
      end

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
    end

    test "disables the Copilot Enterprise features at the enterprise level if no orgs are on Copilot Enterprise plan under mixed licensing" do
      business = create(:business)
      organization = create(:organization, business: business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      enterprise_trial = Copilot::BusinessTrial.create_trial!(organization, create(:staff_admin_user), copilot_plan: "enterprise")

      assert Copilot::Organization.new(organization).copilot_for_dotcom_unconfigured?

      Copilot::Organization.new(organization).copilot_for_dotcom_enabled!

      refute Copilot::Business.new(business).copilot_for_dotcom_disabled?
      refute Copilot::Organization.new(organization).copilot_for_dotcom_disabled?

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        assert_logged("Body" => "Disabling Copilot Enterprise features for the business", "gh.business.id" => business.id) do
          enterprise_trial.process_disabling_copilot_enterprise_features
        end
      end

      assert Copilot::Business.new(business).copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(organization).copilot_for_dotcom_disabled?
    end
  end

  context "#was_created_by_staff_user" do
    test "returns false if managing user is not a staff user" do
      trialable = create(:organization, :enterprise_linked)
      regular_user = create(:user)
      trial = create(:copilot_business_trial, :upgraded, :organization, trialable: trialable, managing_user: regular_user)

      refute_predicate trial, :was_created_by_staff_user?
    end

    test "returns true if managing user is a staff user" do
      trialable = create(:organization, :enterprise_linked)
      staff_user = create(:employee)
      trial = create(:copilot_business_trial, :upgraded, :organization, trialable: trialable, managing_user: staff_user)

      assert_predicate trial, :was_created_by_staff_user?
    end
  end

  context "#can_force_upgrade?" do
    context "with a parent enterprise" do
      context "active, billable Copilot access" do
        test "returns true when an org has an expired trial" do
          org = create(:organization, :enterprise_linked)
          Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
          Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)

          business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first, copilot_plan: "enterprise")
          Timecop.freeze(5.days.ago) do
            business_trial.start_trial!
            business_trial.update_expiration!(2.days.from_now)
          end

          create(:copilot_seat, organization: org)
          business_trial.check_status!

          Copilot::Business.new(org.business).enable_copilot_for_all_organizations!

          assert business_trial.can_force_upgrade?
        end

        test "returns false otherwise" do
          org = create(:organization, :enterprise_linked)
          Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
          business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first, copilot_plan: "enterprise")
          business_trial.start_trial!

          Copilot::BusinessTrial.states.each_key do |key|
            next if key == "expired"
            business_trial.update!(state: key)

            refute business_trial.can_force_upgrade?
          end
        end
      end

      context "no active, billable Copilot access" do
        test "returns false" do
          org = create(:organization, :enterprise_linked)
          Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

          business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first, copilot_plan: "enterprise")
          Timecop.freeze(5.days.ago) do
            business_trial.start_trial!
            business_trial.update_expiration!(2.days.from_now)
          end

          business_trial.check_status!
          refute business_trial.can_force_upgrade?
        end
      end

      test "returns false when parent is not billable" do
        org = create(:organization, :enterprise_linked)
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

        business_trial = Copilot::BusinessTrial.create_trial!(org, org.admins.first, copilot_plan: "enterprise")
        Timecop.freeze(5.days.ago) do
          business_trial.start_trial!
          business_trial.update_expiration!(2.days.from_now)
        end

        business_trial.check_status!
        refute business_trial.can_force_upgrade?
      end
    end
  end
end if GitHub.copilot_enabled?
