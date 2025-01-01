# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

module OnboardingTasks
  module Businesses
    class EnableCopilotTest < GitHub::TestCase

      fixtures do
        @owner = create :user
        @business = create :business, owners: [@owner]
        @business.update(seats_plan_type: :basic)

        unless GitHub.enterprise?
          @emu = create(:emu, :owner)
          @emu_business = @emu.enterprise_managed_business
          @emu_business.update(seats_plan_type: :basic)
        end
      end

      context "#verify_task" do
        test "returns false if Business has no Copilot team" do
          refute_predicate EnableCopilot.new(taskable: @business, user: @owner), :verify_task
        end

        test "returns false if Business has team with no copilot assignment" do
          create :enterprise_team, business: @business

          refute_predicate EnableCopilot.new(taskable: @business, user: @owner), :verify_task
        end

        test "returns true if Business has Copilot team" do
          enterprise_team = create :enterprise_team, business: @business
          EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)

          assert_predicate EnableCopilot.new(taskable: @business, user: @owner), :verify_task
        end
      end

      context "#completed?" do
        test "returns false if Business has no Copilot team" do
          refute_predicate EnableCopilot.new(taskable: @business, user: @owner), :completed?
        end

        test "returns false if Business has team with no copilot assignment" do
          create :enterprise_team, business: @business

          refute_predicate EnableCopilot.new(taskable: @business, user: @owner), :completed?
        end

        test "returns true if Business has Copilot team" do
          team = create :enterprise_team, business: @business
          EnterpriseTeamAssignment.create!(enterprise_team: team, assignment_type: :copilot)

          assert_predicate EnableCopilot.new(taskable: @business, user: @owner), :completed?
        end
      end

      context "enterprise managed users", skip_enterprise: true do
        context "#verify_task" do
          test "returns false if Business has no Copilot team" do
            refute_predicate EnableCopilot.new(taskable: @emu_business, user: @emu), :verify_task
          end

          test "returns false if Business has team with no copilot assignment" do
            create :enterprise_team, business: @emu_business

            refute_predicate EnableCopilot.new(taskable: @emu_business, user: @emu), :verify_task
          end

          test "returns true if Business has Copilot team" do
            enterprise_team = create :enterprise_team, business: @emu_business
            EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)

            assert_predicate EnableCopilot.new(taskable: @emu_business, user: @emu), :verify_task
          end
        end

        context "#completed?" do
          test "returns false if Business has no Copilot team" do
            refute_predicate EnableCopilot.new(taskable: @emu_business, user: @emu), :completed?
          end

          test "returns false if Business has team with no copilot assignment" do
            create :enterprise_team, business: @emu_business

            refute_predicate EnableCopilot.new(taskable: @emu_business, user: @emu), :completed?
          end

          test "returns true if Business has Copilot team" do
            team = create :enterprise_team, business: @emu_business
            EnterpriseTeamAssignment.create!(enterprise_team: team, assignment_type: :copilot)

            assert_predicate EnableCopilot.new(taskable: @emu_business, user: @emu), :completed?
          end
        end
      end
    end
  end
end
