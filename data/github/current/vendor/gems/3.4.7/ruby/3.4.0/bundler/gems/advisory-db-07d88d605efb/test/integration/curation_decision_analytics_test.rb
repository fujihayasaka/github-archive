# frozen_string_literal: true

require "test_helper"

class CurationDecisionAnalyticsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    CheckSuiteRunner.stubs(run_checks: true)
    CheckSuiteRunner.stubs(checks_passed?: true)
  end

  test "cve_triage close decision is logged with time in queue" do
    Timecop.freeze(Time.current) do
      cve_review = create :cve_review, :curation_state_in_triage

      Timecop.freeze(Time.current + 5) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put close_cve_review_triage_path(cve_review),
            headers: { "X-Okta-Username" => @user.email },
            params: { comment: "Test comment." },
            as: :json

          message = hydro_messages.last
          assert_equal "cve_triage", message[:type]
          assert_equal "close", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal cve_review.ghsa_id, message[:ghsa_id]
          assert_equal 5, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "cve_triage open decision is logged with time in queue" do
    Timecop.freeze(Time.current) do
      cve_review = create :cve_review, :curation_state_in_triage

      Timecop.freeze(Time.current + 6) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put open_cve_review_triage_path(cve_review),
            headers: { "X-Okta-Username" => @user.email },
            params: { assigned_cve_id: "CVE-2021-1234" },
            as: :json

          message = hydro_messages.last
          assert_equal "cve_triage", message[:type]
          assert_equal "open", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal cve_review.ghsa_id, message[:ghsa_id]
          assert_equal 6, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "cve_review publish decision is logged with time in queue" do
    Timecop.freeze(Time.current) do
      cve_review = create :cve_review, :curation_state_open

      Timecop.freeze(Time.current + 99) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put publish_cve_review_path(cve_review),
            headers: { "X-Okta-Username" => @user.email },
            params: { pull_request_url: "https://github.com/CVEProject/cvelist/pull/1537" }

          message = hydro_messages.last
          assert_equal "cve_review", message[:type]
          assert_equal "publish", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal cve_review.ghsa_id, message[:ghsa_id]
          assert_equal 99, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "cve_review#record_curation_decision ignores time previously in queue" do
    Timecop.freeze(Time.current) do
      cve_review = create :cve_review, :curation_state_in_triage

      Timecop.freeze(Time.current + 7) do
        cve_review.decision = :not_assigned
        cve_review.comment = "Nope"
        cve_review.notify!

        Timecop.freeze(Time.current + 8) do
          cve_review.receive_request!

          Timecop.freeze(Time.current + 9) do
            perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
              put open_cve_review_triage_path(cve_review),
                headers: { "X-Okta-Username" => @user.email },
                params: { assigned_cve_id: "CVE-2021-1234" },
                as: :json

              message = hydro_messages.last
              assert_equal "cve_triage", message[:type]
              assert_equal "open", message[:decision]
              assert_equal @user.login, message[:curator_login]
              assert_equal cve_review.ghsa_id, message[:ghsa_id]
              assert_equal 9, message[:time_to_decision_seconds]
            end
          end
        end
      end
    end
  end

  test "cve_review#record_curation_decision ignores time spent waiting in queue" do
    Timecop.freeze(Time.current) do
      cve_review = create :cve_review, :curation_state_waiting

      Timecop.freeze(Time.current + 98) do
        create(:advisory_review, ghsa_id: cve_review.ghsa_id, cve_id: cve_review.assigned_cve_id, feed_entry_type: :repository_advisory_feed_entry)

        Timecop.freeze(Time.current + 97) do
          perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
            put publish_cve_review_path(cve_review),
              headers: { "X-Okta-Username" => @user.email },
              params: { pull_request_url: "https://github.com/CVEProject/cvelist/pull/1537" }

            message = hydro_messages.last
            assert_equal "cve_review", message[:type]
            assert_equal "publish", message[:decision]
            assert_equal @user.login, message[:curator_login]
            assert_equal cve_review.ghsa_id, message[:ghsa_id]
            assert_equal 97, message[:time_to_decision_seconds]
          end
        end
      end
    end
  end

  test "advisory_review close decision is logged with time in queue" do
    # not published
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_open

      Timecop.freeze(Time.current + 50) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put close_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email }

          message = hydro_messages.last
          assert_equal "advisory_review", message[:type]
          assert_equal "close", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 50, message[:time_to_decision_seconds]
        end
      end
    end

    # auto-published
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :open, create_advisory: true
      advisory_review.advisory.update(reviewed: false)

      Timecop.freeze(Time.current + 50) do
        advisory_review.start_review!

        Timecop.freeze(Time.current + 55) do
          perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
            put revert_advisory_review_path(advisory_review),
              headers: { "X-Okta-Username" => @user.email }

            message = hydro_messages.last
            assert_equal "advisory_review", message[:type]
            assert_equal "close", message[:decision]
            assert_equal @user.login, message[:curator_login]
            assert_equal advisory_review.ghsa_id, message[:ghsa_id]
            assert_equal 55, message[:time_to_decision_seconds]
          end
        end
      end
    end
  end

  test "advisory_review ready_to_publish decsision is logged with time in queue" do
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_open

      Timecop.freeze(Time.current + 60) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put approve_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email },
            params: { approval_type: "publish" },
            as: :json

          message = hydro_messages.last
          assert_equal "advisory_review", message[:type]
          assert_equal "ready_to_publish", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 60, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "advisory_review ready_to_withdraw decsision is logged with time in queue" do
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_open

      Timecop.freeze(Time.current + 70) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put approve_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email },
            params: { approval_type: "withdraw" },
            as: :json

          message = hydro_messages.last
          assert_equal "advisory_review", message[:type]
          assert_equal "ready_to_withdraw", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 70, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "advisory_publication close decision is logged with time in queue" do
    # not autopublished, intented to publish
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_ready_to_publish

      Timecop.freeze(Time.current + 80) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put close_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email }

          message = hydro_messages.last
          assert_equal "advisory_publication", message[:type]
          assert_equal "close", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 80, message[:time_to_decision_seconds]
        end
      end
    end

    # autopublished, intended to withdraw
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_ready_to_withdraw
      advisory_review.advisory.update(reviewed: false)

      Timecop.freeze(Time.current + 90) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put revert_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email }

          message = hydro_messages.last
          assert_equal "advisory_publication", message[:type]
          assert_equal "close", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 90, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "advisory_publication publish decision is logged with time spent in queue" do
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_ready_to_publish

      Timecop.freeze(Time.current + 999) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put publish_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email }

          message = hydro_messages.last
          assert_equal "advisory_publication", message[:type]
          assert_equal "publish", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 999, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "advisory_publication withdraw decision is logged with time spent in queue" do
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_ready_to_withdraw

      Timecop.freeze(Time.current + 998) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put withdraw_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email }

          message = hydro_messages.last
          assert_equal "advisory_publication", message[:type]
          assert_equal "withdraw", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 998, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "advisory_update close decision is logged with time spent in queue" do
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_open_update

      Timecop.freeze(Time.current + 888) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put revert_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email }

          message = hydro_messages.last
          assert_equal "advisory_update", message[:type]
          assert_equal "close", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 888, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "advisory_update ready_to_withdraw decision is logged with time spent in queue" do
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_open_update

      Timecop.freeze(Time.current + 777) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put approve_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email },
            params: { approval_type: "withdraw" },
            as: :json

          message = hydro_messages.last
          assert_equal "advisory_update", message[:type]
          assert_equal "ready_to_withdraw", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 777, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "advisory_update publsih decision is logged with time spent in queue" do
    Timecop.freeze(Time.current) do
      advisory_review = create :advisory_review, :curation_state_open_update

      Timecop.freeze(Time.current + 666) do
        perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
          put publish_advisory_review_path(advisory_review),
            headers: { "X-Okta-Username" => @user.email }

          message = hydro_messages.last
          assert_equal "advisory_update", message[:type]
          assert_equal "publish", message[:decision]
          assert_equal @user.login, message[:curator_login]
          assert_equal advisory_review.ghsa_id, message[:ghsa_id]
          assert_equal 666, message[:time_to_decision_seconds]
        end
      end
    end
  end

  test "advisory_review#record_curation_decision ignores time previously in queue" do
    Timecop.freeze(Time.current.to_i) do
      advisory_review = create :advisory_review, :open

      Timecop.freeze(Time.current + 12) do
        advisory_review.close!

        Timecop.freeze(Time.current + 13) do
          advisory_review.reopen!

          Timecop.freeze(Time.current + 14) do
            perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
              put approve_advisory_review_path(advisory_review),
                headers: { "X-Okta-Username" => @user.email },
                params: { approval_type: "publish" },
                as: :json

              message = hydro_messages.last
              assert_equal "advisory_review", message[:type]
              assert_equal "ready_to_publish", message[:decision]
              assert_equal @user.login, message[:curator_login]
              assert_equal advisory_review.ghsa_id, message[:ghsa_id]
              assert_equal 14, message[:time_to_decision_seconds]
            end
          end
        end
      end
    end
  end

  test "advisory_review#record_curation_decision ignores time spent waiting in queue" do
    Timecop.freeze(Time.current.to_i) do
      advisory_review = create :advisory_review, :open, feed_entry_type: :cve_review_feed_entry

      Timecop.freeze(Time.current + 12) do
        advisory_review.start_review!

        Timecop.freeze(Time.current + 13) do
          repo_feed = create :repository_advisory_feed_entry, ghsa_id: advisory_review.ghsa_id
          ResolveFeedEntryJob.new.perform(repo_feed.id)

          Timecop.freeze(Time.current + 14) do
            perform_enqueued_jobs(only: [PublishCurationDecisionToHydroJob]) do
              put approve_advisory_review_path(advisory_review),
                headers: { "X-Okta-Username" => @user.email },
                params: { approval_type: "publish" },
                as: :json

              message = hydro_messages.last
              assert_equal "advisory_review", message[:type]
              assert_equal "ready_to_publish", message[:decision]
              assert_equal @user.login, message[:curator_login]
              assert_equal advisory_review.ghsa_id, message[:ghsa_id]
              assert_equal 14, message[:time_to_decision_seconds]
            end
          end
        end
      end
    end
  end
end
