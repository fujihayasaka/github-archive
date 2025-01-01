# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class FeedbackLinkTest < GitHub::TestCase
    PUBLIC_FEEDBACK_URL = "https://github.com/orgs/community/discussions/categories/code-security"

    fixtures do
      @admin = create(:user)
      @member = create(:user)
      @org = create(:organization, name: "github-early-access", admin: @admin)
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @admin)
      end
      @org.add_member(@member)

      create(:private_repository, has_discussions: true, owner: @org, name: "security-overview-private-beta-community")

      @private_phases = FeedbackLink::PRIVATE_FEEDBACK_PHASES
      @public_phases = Phase::VALID_PHASES - @private_phases
    end

    setup do
      enable_feature_flag(:security_center_private_beta)
    end

    test "raises an error for unknown phases" do
      assert_raises(ArgumentError) { FeedbackLink.new(phase: :unknown, actor: @admin, scope: @org) }
    end

    test "defaults to ga phase" do
      feedback = FeedbackLink.new(actor: @member, scope: @org)
      assert_equal "Give feedback", feedback.text
      assert_equal PUBLIC_FEEDBACK_URL, feedback.url
    end

    context "text" do
      test "returns 'Give feedback' for the public feedback URL" do
        feedback = FeedbackLink.new(phase: :ga, actor: @member, scope: @org)
        assert_equal "Give feedback", feedback.text
      end

      context "dotcom request", skip_enterprise: true do
        test "returns 'Get updates and share feedback' for the private feedback URL" do
          feedback = FeedbackLink.new(phase: :ga, actor: @admin, scope: @org)
          assert_equal "Get updates and share feedback", feedback.text
        end
      end
    end

    context "url" do
      context "public phases" do
        test "returns public feedback URL if the actor is not in the private beta group" do
          disable_feature_flag(:security_center_private_beta)
          @public_phases.each do |p|
            feedback = FeedbackLink.new(phase: p, actor: @admin, scope: @org)
            assert_equal PUBLIC_FEEDBACK_URL, feedback.url
          end
        end

        context "actor is in the private beta group" do
          test "returns public feedback URL for enterprise requests", enterprise_only: true do
            @public_phases.each do |p|
              feedback = FeedbackLink.new(phase: p, actor: @admin, scope: @org)
              assert_equal PUBLIC_FEEDBACK_URL, feedback.url
            end
          end

          context "dotcom request", skip_enterprise: true do
            test "returns public feedback URL if the private feedback repo does not exist" do
              Repository.stubs(:nwo).with("github-early-access/security-overview-private-beta-community", search_redirects: true).returns(nil)
              @public_phases.each do |p|
                feedback = FeedbackLink.new(phase: p, actor: @admin, scope: @org)
                assert_equal PUBLIC_FEEDBACK_URL, feedback.url
              end
            end

            context "private feedback repo exists" do
              test "returns public feedback URL if the actor cannot read the private feedback repo" do
                @public_phases.each do |p|
                  feedback = FeedbackLink.new(phase: p, actor: @member, scope: @org)
                  assert_equal PUBLIC_FEEDBACK_URL, feedback.url
                end
              end

              context "actor can read the private feedback repo" do
                test "returns private feedback URL for public phases" do
                  expected_href = "/github-early-access/security-overview-private-beta-community/discussions"
                  @public_phases.each do |p|
                    feedback = FeedbackLink.new(phase: p, actor: @admin, scope: @org)
                    assert_equal expected_href, feedback.url
                  end
                end
              end
            end
          end
        end
      end

      context "private phases" do
        test "returns nil url if the actor is not in the private beta group" do
          disable_feature_flag(:security_center_private_beta)
          @private_phases.each do |p|
            feedback = FeedbackLink.new(phase: p, actor: @admin, scope: @org)
            assert_nil feedback.url
          end
        end

        context "actor is in the private beta group" do
          test "returns nil url for enterprise requests", enterprise_only: true do
            @private_phases.each do |p|
              feedback = FeedbackLink.new(phase: p, actor: @admin, scope: @org)
              assert_nil feedback.url
            end
          end

          context "dotcom request", skip_enterprise: true do
            test "returns nil url if the private feedback repo does not exist" do
              Repository.stubs(:nwo).with("github-early-access/security-overview-private-beta-community", search_redirects: true).returns(nil)
              @private_phases.each do |p|
                feedback = FeedbackLink.new(phase: p, actor: @admin, scope: @org)
                assert_nil feedback.url
              end
            end

            context "private feedback repo exists" do
              test "returns nil url when the actor cannot read the private feedback repo" do
                @private_phases.each do |p|
                  feedback = FeedbackLink.new(phase: p, actor: @member, scope: @org)
                  assert_nil feedback.url
                end
              end

              context "actor can read the private feedback repo" do
                test "returns private feedback URL" do
                  expected_href = "/github-early-access/security-overview-private-beta-community/discussions"
                  @private_phases.each do |p|
                    feedback = FeedbackLink.new(phase: p, actor: @admin, scope: @org)
                    assert_equal expected_href, feedback.url
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
