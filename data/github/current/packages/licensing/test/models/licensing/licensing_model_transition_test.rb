# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::LicensingModelTransitionTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @user = create(:user)
  end

  test "requires a customer" do
    transition = Licensing::LicensingModelTransition.new
    refute transition.valid?
    refute_empty transition.errors[:customer]
  end

  test "requires a valid licensing_model" do
    assert_raises ArgumentError do
      Licensing::LicensingModelTransition.new(
        licensing_model: "invalid",
        ghas_only: false
      )
    end
  end

  test "requires a valid status" do
    assert_raises ArgumentError do
      Licensing::LicensingModelTransition.new(
        status: "invalid",
        ghas_only: false
      )
    end
  end

  test "requires GHAS only to be set" do
    transition = Licensing::LicensingModelTransition.new(
      licensing_model: "metered",
      status: "scheduled",
      customer: @business.customer,
      actor: @user,
      transition_date: 2.days.from_now,
      ghas_only: nil
    )

    refute transition.valid?
    refute_empty transition.errors[:ghas_only]
  end

  test "requires a transition_date" do
    transition = Licensing::LicensingModelTransition.new
    refute transition.valid?
    refute_empty transition.errors[:transition_date]
  end

  test "Transition must be in the future" do
    transition = Licensing::LicensingModelTransition.new(
      transition_date: 2.days.ago,
      customer: @business.customer,
      licensing_model: "metered",
      actor: @user,
      ghas_only: false
    )
    refute transition.valid?
    refute_empty transition.errors[:transition_date]
  end

  test "Must be moving to a new license model" do
    transition = Licensing::LicensingModelTransition.new(
      transition_date: 1.day.from_now,
      licensing_model: "volume",
      customer: @business.customer,
      status: "scheduled",
      actor: @user,
      ghas_only: false
    )
    refute transition.valid?
    refute_empty transition.errors[:licensing_model]
  end

  test "Can't schedule two transitions for the same customer" do
    create(:licensing_licensing_model_transition, customer: @business.customer)
    transition = Licensing::LicensingModelTransition.new(
      transition_date: 1.day.from_now,
      licensing_model: "metered",
      customer: @business.customer,
      status: "scheduled",
      actor: @user,
      ghas_only: false
    )
    refute transition.valid?
    refute_empty transition.errors[:status]
  end

  test "Can't schedule ghas only transitions with the volume licensing model" do
    create(:licensing_licensing_model_transition, customer: @business.customer)
    transition = Licensing::LicensingModelTransition.new(
      transition_date: 1.day.from_now,
      licensing_model: "volume",
      customer: @business.customer,
      status: "scheduled",
      actor: @user,
      ghas_only: true
    )
    refute transition.valid?
    refute_empty transition.errors[:ghas_only]
  end

  context "#enqueue" do
    test "enqueues a metered licensing model transition" do
      transition = create(
        :licensing_licensing_model_transition,
        customer: @business.customer,
        actor: @user
      )

      assert_enqueued_jobs 1, only: Licensing::TransitionEnterpriseToMeteredLicensingJob do
        transition.enqueue
      end
    end

    test "enqueues a metered licensing model transition that should have run yesterday" do
      transition = create(
        :licensing_licensing_model_transition,
        transition_date: 1.day.from_now,
        customer: @business.customer,
        actor: @user
      )

      Timecop.freeze(3.days.from_now) do
        assert_enqueued_jobs 1, only: Licensing::TransitionEnterpriseToMeteredLicensingJob do
          Licensing::TriggerScheduledLicensingModelTransitionsJob.perform_now
        end
      end
    end

    test "enqueues a volume licensing model transition" do
      @business.customer.update!(metered_plan: true)
      transition = create(
        :licensing_licensing_model_transition,
        customer: @business.customer,
        licensing_model: "volume",
        actor: @user
      )

      assert_enqueued_jobs 1, only: Licensing::TransitionEnterpriseToVolumeLicensingJob do
        transition.enqueue
      end
    end

    test "enqueues a transition job to unbundle GHAS on metered if feature flag is enabled", skip_enterprise: true do
      transition = create(
        :licensing_licensing_model_transition,
        customer: @business.customer,
        actor: @user
      )

      enable_feature_flag(:ghas_unbundle_transitions)

      assert_enqueued_jobs 1, only: Licensing::TransitionUnbundleGhasForBusinessJob do
        transition.enqueue
      end
    end

    test "does not enqueue GHAS unbundling jobs for metered if feature flag is disabled", skip_enterprise: true do
      transition = create(
        :licensing_licensing_model_transition,
        customer: @business.customer,
        actor: @user
      )

      disable_feature_flag(:ghas_unbundle_transitions)

      assert_enqueued_jobs 0, only: Licensing::TransitionUnbundleGhasForBusinessJob do
        transition.enqueue
      end
    end

    test "enqueues a transition job to rebundle GHAS on volume if feature flag is enabled", skip_enterprise: true do
      @business.customer.update!(metered_plan: true)
      transition = create(
        :licensing_licensing_model_transition,
        licensing_model: "volume",
        customer: @business.customer,
        actor: @user
      )

      enable_feature_flag(:ghas_unbundle_transitions)

      assert_enqueued_jobs 1, only: Licensing::TransitionRebundleGhasForBusinessJob do
        transition.enqueue
      end
    end

    test "does not enqueue a transition job to rebundle GHAS on volume if feature flag is disabled", skip_enterprise: true do
      @business.customer.update!(metered_plan: true)
      transition = create(
        :licensing_licensing_model_transition,
        licensing_model: "volume",
        customer: @business.customer,
        actor: @user
      )

      disable_feature_flag(:ghas_unbundle_transitions)

      assert_enqueued_jobs 0, only: Licensing::TransitionRebundleGhasForBusinessJob do
        transition.enqueue
      end
    end
  end
end
