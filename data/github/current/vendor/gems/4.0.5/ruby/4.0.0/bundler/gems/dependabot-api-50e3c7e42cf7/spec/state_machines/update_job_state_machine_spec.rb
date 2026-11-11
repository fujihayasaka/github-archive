# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateJobStateMachine do
  include ActiveSupport::Testing::TimeHelpers

  describe "guards" do
    describe "to processed_with_errors" do
      let(:update_job) { FactoryBot.create(:update_job, :processing) }

      context "with errors" do
        let(:errors) { [{ "error-type" => "bad" }] }

        it "can transition" do
          expect do
            update_job.transition_to!(:processed_with_errors, errors: errors)
          end.not_to raise_error
        end
      end

      context "without any errors" do
        it "can't transition" do
          expect do
            update_job.transition_to!(:processed_with_errors, errors: [])
          end.to raise_error(Statesman::GuardFailedError)
        end
      end

      context "without an errors metadata key" do
        it "can't transition" do
          expect { update_job.transition_to!(:processed_with_errors) }.
            to raise_error(Statesman::GuardFailedError)
        end
      end
    end

    describe "to abandoned from timed_out" do
      let(:update_job) { FactoryBot.create(:update_job, :timed_out) }

      context "when self-hosted" do
        before do
          allow(update_job).to receive(:self_hosted?).and_return(true)
        end

        it "can transition" do
          expect do
            update_job.transition_to!(:abandoned)
          end.not_to raise_error
        end
      end

      context "when not self-hosted" do
        before do
          allow(update_job).to receive(:self_hosted?).and_return(false)
        end

        it "can't transition" do
          expect do
            update_job.transition_to!(:abandoned)
          end.to raise_error(Statesman::GuardFailedError)
        end
      end
    end
  end

  describe "callbacks" do
    describe "to enqueued" do
      let(:update_job) do
        FactoryBot.create(:update_job, :pending, created_at: 1.hour.ago)
      end
      let(:transition_job) do
        lambda do
          update_job.transition_to!(
            :enqueued,
            hashed_token: "a-hashed-token",
            hashed_credentials_token: "another-hashed-token",
          )
        end
      end

      it "stores the hashed job token on the job" do
        expect { transition_job.call }.
          to change(update_job, :hashed_token).
          from(nil).to("a-hashed-token")
      end

      it "stores the hashed credentials token on the job" do
        expect { transition_job.call }.
          to change(update_job, :hashed_credentials_token).
          from(nil).to("another-hashed-token")
      end

      it "doesn't store either hashed token on the transition" do
        transition_job.call
        expect(update_job.last_transition(force_reload: true).metadata).
          to be_empty
      end

      it "sends the right timings to MetricsClient" do
        expect(MetricsClient).to receive(:timing).
          with("update_job.transition.time", anything, anything)
        expect(MetricsClient).to receive(:count).
          with("update_job.transitioned", 1, anything)
        transition_job.call
      end
    end

    describe "from enqueued back to pending" do
      let(:update_job) { create(:update_job, :pending, :on_gh_actions, created_at: 1.hour.ago) }
      let(:transition_job) do
        lambda do
          update_job.transition_to!(:pending)
        end
      end

      before do
        update_job.transition_to!(
          :enqueued,
          hashed_token: "a-hashed-token",
          hashed_credentials_token: "another-hashed-token",
        )
      end

      it "removes the hashed job token on the job" do
        expect { transition_job.call }.
          to change(update_job, :hashed_token).
          from("a-hashed-token").to(nil)
      end

      it "removes the hashed credentials token on the job" do
        expect { transition_job.call }.
          to change(update_job, :hashed_credentials_token).
          from("another-hashed-token").to(nil)
      end

      it "enqueues a job to cancel an actions workflow" do
        expect { transition_job.call }.
          to enqueue_job(CancelActionsWorkflowRunJob).with(update_job, update_job.actions_workflow_run_id)
      end
    end

    describe "from enqueued to abandoned" do
      let(:update_job) { create(:update_job, :pending, :on_gh_actions, created_at: 1.hour.ago) }
      let(:transition_job) do
        -> { update_job.transition_to!(:abandoned) }
      end

      before do
        update_job.transition_to!(
          :enqueued,
          hashed_token: "a-hashed-token",
          hashed_credentials_token: "another-hashed-token",
        )
      end

      it "removes the hashed job token on the job" do
        expect { transition_job.call }.
          to change(update_job, :hashed_token).
          from("a-hashed-token").to(nil)
      end

      it "removes the hashed credentials token on the job" do
        expect { transition_job.call }.
          to change(update_job, :hashed_credentials_token).
          from("another-hashed-token").to(nil)
      end

      it "enqueues a job to cancel an actions workflow" do
        expect { transition_job.call }.
          to enqueue_job(CancelActionsWorkflowRunJob).with(update_job, update_job.actions_workflow_run_id)
      end
    end

    describe "to processing" do
      let(:update_job) do
        FactoryBot.create(:update_job, :enqueued, created_at: 1.hour.ago)
      end
      let(:transition_job) { -> { update_job.transition_to!(:processing) } }

      it "sets expires_at on the job" do
        freeze_time do
          expires_at = Time.now.in_time_zone + update_job.max_run_time
          expect { transition_job.call }.to change(update_job, :expires_at).
            from(nil).to(expires_at)
        end
      end
    end

    describe "to processed" do
      let(:update_job) do
        FactoryBot.create(:update_job, :processing, created_at: 5.hours.ago)
      end
      let(:transition_job) { -> { update_job.transition_to!(:processed) } }

      before do
        ordered_transitions = update_job.update_job_transitions.order(:sort_key)
        ordered_transitions[-1].update!(created_at: 5.minutes.ago)
        ordered_transitions[-2].update!(created_at: 20.minutes.ago)
      end

      it "sends the right timings to MetricsClient" do
        expect(MetricsClient).to receive(:timing).
          with("update_job.transition.time", anything, anything)
        expect(MetricsClient).to receive(:count).
          with("update_job.transitioned", 1, anything)
        transition_job.call
      end
    end
  end

  describe "group transition logging" do
    let(:dependency_group) { FactoryBot.create(:dependency_group, name: "test-group") }
    let(:grouped_update_config) { FactoryBot.create(:update_config, dependency_groups: [dependency_group]) }
    let(:update_job) { FactoryBot.create(:update_job, :enqueued, update_config: grouped_update_config) }

    before do
      allow(Dependabot::Logger).to receive(:info)
      allow(Dependabot::Logger).to receive(:warn)
    end

    context "when transitioning to abandoned state" do
      it "logs potential silent failure for group jobs" do
        update_job.transition_to!(:abandoned)

        expect(Dependabot::Logger).to have_received(:warn).with(
          hash_including(
            msg: "Group update job abandoned - potential silent failure",
            potential_silent_failure: true,
            "gh.dependabot_api.update_job.to_state": "abandoned"
          )
        )
      end

      it "emits silent failure metric for group jobs" do
        update_job.transition_to!(:abandoned)

        expect(MetricsClient).to have_received(:count).
          with("grouped_update.silent_failure", 1, hash_including(
                                                     tags: hash_including(
                                                       reason: "abandoned",
                                                       from_state: "enqueued",
                                                       grouped_update: true,
                                                       group_count: 1,
                                                       group_names: "test-group"
                                                     )
                                                   ))
      end
    end

    context "when transitioning to timed_out state" do
      let(:update_job) { FactoryBot.create(:update_job, :processing, update_config: grouped_update_config) }

      it "logs potential silent failure for group jobs" do
        update_job.transition_to!(:timed_out)

        expect(Dependabot::Logger).to have_received(:warn).with(
          hash_including(
            msg: "Group update job timed out - potential silent failure",
            potential_silent_failure: true,
            "gh.dependabot_api.update_job.to_state": "timed_out"
          )
        )
      end

      it "emits silent failure metric for group jobs" do
        update_job.transition_to!(:timed_out)

        expect(MetricsClient).to have_received(:count).
          with("grouped_update.silent_failure", 1, hash_including(
                                                     tags: hash_including(
                                                       reason: "timed_out",
                                                       from_state: "processing",
                                                       grouped_update: true,
                                                       group_count: 1,
                                                       group_names: "test-group"
                                                     )
                                                   ))
      end
    end

    context "when transitioning to processed state" do
      let(:update_job) { FactoryBot.create(:update_job, :processing, update_config: grouped_update_config) }

      context "with pending pull requests" do
        before do
          allow(PendingPullRequest).to receive(:exists?).with(update_job_id: update_job.id).and_return(true)
        end

        it "logs successful completion for group jobs" do
          update_job.transition_to!(:processed)

          expect(Dependabot::Logger).to have_received(:info).with(
            hash_including(
              msg: "Group update job completed successfully",
              "gh.dependabot_api.update_job.to_state": "processed"
            )
          )
        end

        it "emits successful completion metric for group jobs" do
          update_job.transition_to!(:processed)

          expect(MetricsClient).to have_received(:count).
            with("grouped_update.completed_successfully", 1, hash_including(
                                                               tags: hash_including(
                                                                 grouped_update: true,
                                                                 group_count: 1,
                                                                 group_names: "test-group"
                                                               )
                                                             ))
        end

        it "does not emit no PR created metric when PRs exist" do
          update_job.transition_to!(:processed)

          expect(MetricsClient).not_to have_received(:count).
            with("grouped_update.no_pr_created", anything)
        end
      end

      context "without pending pull requests (silent failure)" do
        before do
          allow(PendingPullRequest).to receive(:exists?).with(update_job_id: update_job.id).and_return(false)
        end

        context "when update job has errors" do
          before do
            update_job.update_job_errors.create!(error_type: "dependency_resolution_failed")
          end

          it "emits no PR created metric with dependency resolution failed reason" do
            update_job.transition_to!(:processed)

            expect(MetricsClient).to have_received(:count).
              with("grouped_update.no_pr_created", 1, hash_including(
                                                        tags: hash_including(
                                                          reason: "dependency_resolution_failed",
                                                          grouped_update: true,
                                                          group_count: 1,
                                                          group_names: "test-group"
                                                        )
                                                      ))
          end
        end

        context "when dependencies array is empty" do
          before do
            allow(update_job).to receive(:dependencies).and_return([])
          end

          it "emits no PR created metric with no dependencies specified reason" do
            update_job.transition_to!(:processed)

            expect(MetricsClient).to have_received(:count).
              with("grouped_update.no_pr_created", 1, hash_including(
                                                        tags: hash_including(
                                                          reason: "no_dependencies_specified",
                                                          grouped_update: true,
                                                          group_count: 1,
                                                          group_names: "test-group"
                                                        )
                                                      ))
          end
        end

        context "when existing PR found for dependencies" do
          let(:example_gem) { { "name" => "example-gem", "version" => "1.0.0" } }
          let(:another_gem) { { "name" => "another-gem", "version" => "2.0.0" } }

          before do
            allow(update_job).to receive(:dependencies).and_return([example_gem, another_gem])
            # Mock the private method that checks for existing PRs
            allow(described_class).to receive(:existing_pr_for_dependencies?).with(update_job).and_return(true)
          end

          it "emits no PR created metric with existing PR found reason" do
            update_job.transition_to!(:processed)

            expect(MetricsClient).to have_received(:count).
              with("grouped_update.no_pr_created", 1, hash_including(
                                                        tags: hash_including(
                                                          reason: "existing_pr_found",
                                                          grouped_update: true,
                                                          group_count: 1,
                                                          group_names: "test-group"
                                                        )
                                                      ))
          end
        end

        context "when no updates available" do
          let(:example_gem) { { "name" => "example-gem", "version" => "1.0.0" } }

          before do
            allow(update_job).to receive(:dependencies).and_return([example_gem])
            allow(PendingPullRequest).to receive(:where).and_return(
              instance_double(ActiveRecord::Relation, exists?: false)
            )
          end

          it "emits no PR created metric with no updates available reason" do
            update_job.transition_to!(:processed)

            expect(MetricsClient).to have_received(:count).
              with("grouped_update.no_pr_created", 1, hash_including(
                                                        tags: hash_including(
                                                          reason: "no_updates_available",
                                                          grouped_update: true,
                                                          group_count: 1,
                                                          group_names: "test-group"
                                                        )
                                                      ))
          end
        end

        it "logs successful completion for group jobs even without PRs" do
          update_job.transition_to!(:processed)

          expect(Dependabot::Logger).to have_received(:info).with(
            hash_including(
              msg: "Group update job completed successfully",
              "gh.dependabot_api.update_job.to_state": "processed"
            )
          )
        end

        it "still emits successful completion metric" do
          update_job.transition_to!(:processed)

          expect(MetricsClient).to have_received(:count).
            with("grouped_update.completed_successfully", 1, hash_including(
                                                               tags: hash_including(
                                                                 grouped_update: true,
                                                                 group_count: 1,
                                                                 group_names: "test-group"
                                                               )
                                                             ))
        end
      end
    end

    context "when transitioning to processed_with_errors state" do
      let(:update_job) { FactoryBot.create(:update_job, :processing, update_config: grouped_update_config) }
      let(:errors) { [{ "error-type" => "dependency_file_not_found" }, { "error-type" => "unknown_error" }] }

      before do
        # Create actual UpdateJobError records so the state machine can access them
        update_job.update_job_errors.create!(error_type: "dependency_file_not_found")
        update_job.update_job_errors.create!(error_type: "unknown_error")
      end

      it "logs errors for group jobs" do
        update_job.transition_to!(:processed_with_errors, errors: errors)

        expect(Dependabot::Logger).to have_received(:warn).with(
          hash_including(
            msg: "Group update job completed with errors",
            error_types: %w(dependency_file_not_found unknown_error),
            error_count: 2
          )
        )
      end

      it "emits error completion metric for group jobs" do
        update_job.transition_to!(:processed_with_errors, errors: errors)

        expect(MetricsClient).to have_received(:count).
          with("grouped_update.completed_with_errors", 1, hash_including(
                                                            tags: hash_including(
                                                              primary_error_type: "dependency_file_not_found",
                                                              error_count: 2,
                                                              grouped_update: true,
                                                              group_count: 1,
                                                              group_names: "test-group"
                                                            )
                                                          ))
      end
    end
  end

  describe "denormalizing current state" do
    let(:update_job) { create(:update_job) }

    it "sets the current_state column on transition" do
      expect(update_job.current_state).to eq("pending")

      update_job.transition_to!(:enqueued)
      update_job.reload
      expect(update_job.attributes["current_state"]).to eq("enqueued")

      update_job.transition_to!(:processing)
      update_job.reload
      expect(update_job.attributes["current_state"]).to eq("processing")
    end

    it "resetting the state machine reloads the denormalized column" do
      update_job.current_state = "enqueued"
      update_job.state_machine.reset
      expect(update_job.current_state).to eq("pending")
    end
  end
end
