# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessStartupsProgramTest < GitHub::TestCase

  context "validating emails_sent_at keys" do
    test "accepts valid key" do
      startups_program = build(:business_startups_program, emails_sent_at: { email_30_day_year_1: Time.now })

      assert startups_program.valid?
    end

    test "rejects invalid key" do
      startups_program = build(:business_startups_program, emails_sent_at: { invalid_key: Time.now })

      refute startups_program.valid?
    end
  end

  context "email_sent?" do
    test "returns true if specificic email is sent" do
      startups_program = build(:business_startups_program, emails_sent_at: { email_30_day_year_1: Time.now })

      assert startups_program.email_sent?(:email_30_day_year_1)
    end

    test "returns false if empty" do
      startups_program = build(:business_startups_program, emails_sent_at: {})

      refute startups_program.email_sent?(:email_30_day_year_1)
    end

    test "returns false if email if key is empty" do
      startups_program = build(:business_startups_program, emails_sent_at: { email_30_day_year_1: Time.now })

      refute startups_program.email_sent?(:email_3_day_year_1)
    end
  end

  context "create or update" do
    test "creates a startups program if it does not exist" do
      business = create(:business)

      assert_difference("::BusinessStartupsProgram.count", 1) do
        BusinessStartupsProgram.create_or_update!(business, "year_2")
      end
      assert_predicate business.reload.startups_program, :year_2?
      assert_predicate business, :part_of_startup_program?
    end

    test "updates the startups program if it exists" do
      business = create(:business)
      startups_program = create(:business_startups_program, business: business, status: :year_1)

      assert_difference("::BusinessStartupsProgram.count", 0) do
        BusinessStartupsProgram.create_or_update!(business, "year_2")
      end
      assert_predicate startups_program.reload, :year_2?
      assert_predicate business, :part_of_startup_program?
    end

    test "removes from program if status is removed" do
      business = create(:business)
      startups_program = create(:business_startups_program, business: business, status: :year_1)

      assert_difference("::BusinessStartupsProgram.count", 0) do
        BusinessStartupsProgram.create_or_update!(business, "removed")
      end
      assert_predicate startups_program.reload, :removed?
      refute business.part_of_startup_program?
    end
  end

  context "currently_in_the_program?" do
    test "belongs to program if status is year_1, year_2 or graduated" do
      %w(year_1 year_2 graduated).each do |status|
        assert BusinessStartupsProgram.currently_in_the_program?(status)
        assert BusinessStartupsProgram.new(status: status).currently_in_the_program?
      end
    end

    test "does not belong to program if status is removed or nil" do
      ["removed", nil].each do |status|
        refute BusinessStartupsProgram.currently_in_the_program?(status)
      end
      refute BusinessStartupsProgram.new(status: "removed").currently_in_the_program?
    end
  end

  context "welcome email" do
    if GitHub.single_business_environment?
      test "does not send a welcome email in single business environment" do
        owner = create(:user)
        business = create(:business, owners: [owner])
        startups_program = create(:business_startups_program, business: business)

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_no_difference "ActionMailer::Base.deliveries.size" do
            startups_program.send_welcome_email
          end
        end
      end
    else
      test "sends welcome email when part_of_startup_program set to true" do
        Timecop.freeze("2024-03-27T00:00:00.000Z") do
          owner = create(:user)
          business = create(:business, owners: [owner])
          startups_program = create(:business_startups_program, business: business)

          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            assert_difference "ActionMailer::Base.deliveries.size", +1 do
              startups_program.send_welcome_email
            end
          end

          assert_predicate business.reload, :part_of_startup_program?
          mail = ActionMailer::Base.deliveries.last
          assert_equal "Welcome to GitHub for Startups", mail.subject
          assert_equal "2024-03-27T00:00:00.000Z", startups_program.reload.emails_sent_at["welcome"]
        end
      end

      test "does not send a welcome email if there are no owners" do
        business = create(:business, owners: [])
        startups_program = create(:business_startups_program, business: business)

        assert_empty business.owners
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_no_difference "ActionMailer::Base.deliveries.size" do
            startups_program.send_welcome_email
          end
        end
      end

      test "does not send a welcome email twice" do
        owner = create(:user)
        business = create(:business, owners: [owner])
        startups_program = create(:business_startups_program, business: business)

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_difference "ActionMailer::Base.deliveries.size", +1 do
            startups_program.send_welcome_email
          end
        end

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_no_difference "ActionMailer::Base.deliveries.size" do
            startups_program.send_welcome_email
          end
        end
      end

      test "does not send if status is not year 1" do
        owner = create(:user)
        business = create(:business, owners: [owner])
        startups_program = create(:business_startups_program, business: business, status: :year_2)

        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_no_difference "ActionMailer::Base.deliveries.size" do
            startups_program.send_welcome_email
          end
        end
      end

      BusinessStartupsProgram::EMAIL_TYPES.each do |email_type|
        test "does not send email if any #{email_type} was already sent" do
          owner = create(:user)
          business = create(:business, owners: [owner])
          startups_program = create(:business_startups_program, business: business, status: :year_1)

          startups_program.emails_sent_at[email_type.to_s] = Time.now
          startups_program.save!

          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            assert_no_difference "ActionMailer::Base.deliveries.size" do
              startups_program.send_welcome_email
            end
          end
        end
      end
    end
  end
end
