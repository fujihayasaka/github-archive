# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20251230042641_backfill_current_state_values.rb"

RSpec.describe "Dependabot::Transitions::BackfillCurrentStateValues" do
  def transition(**args)
    args[:dry_run] = false unless args.key?(:dry_run)
    Dependabot::Transitions::BackfillCurrentStateValues.new(**args)
  end

  let(:freno_throttler) { instance_double(Freno::Throttler) }

  before do
    # create 2 each of the records to work with
    create_list(:account, 2)
    Account.find_each do |account|
      repo = create(:repo, account: account)
      update_config = create(:update_config, repo: repo)
      update_job = create(:update_job, update_config: update_config)
      create(:pull_request, repo: repo, update_job: update_job)
      create(:pending_pull_request, update_job: update_job)
    end

    allow(freno_throttler).
      to receive(:throttle).
      with(Dependabot::Transitions::BackfillCurrentStateValues::FRENO_CLUSTER).
      and_yield
    allow(Dependabot).to receive(:freno_throttler).and_return(freno_throttler)
  end

  context "write" do
    it "updates current_state to initial state when there haven't been any transitions" do # rubocop:disable RSpec/ExampleLength
      # Set all current_state values to nil to simulate missing data
      Account.update_all(current_state: nil)
      UpdateConfig.update_all(current_state: nil)
      UpdateJob.update_all(current_state: nil)
      PullRequest.update_all(current_state: nil)
      PendingPullRequest.update_all(current_state: nil)

      expect(Account.where(current_state: nil).count).to be 2
      expect(UpdateConfig.where(current_state: nil).count).to be 2
      expect(UpdateJob.where(current_state: nil).count).to be 2
      expect(PullRequest.where(current_state: nil).count).to be 2
      expect(PendingPullRequest.where(current_state: nil).count).to be 2

      transition.perform

      expect(Account.where(current_state: AccountStateMachine.initial_state).count).to be 2
      expect(UpdateConfig.where(current_state: UpdateConfigStateMachine.initial_state).count).to be 2
      expect(UpdateJob.where(current_state: UpdateJobStateMachine.initial_state).count).to be 2
      expect(PullRequest.where(current_state: PullRequestStateMachine.initial_state).count).to be 2
      expect(PendingPullRequest.where(current_state: PendingPullRequestStateMachine.initial_state).count).to be 2
    end

    it "updates current_state to the current state based on the latest transition" do # rubocop:disable RSpec/ExampleLength
      # transition all records to a non-initial state and set current_state to nil
      # to simulate missing current_state
      Account.find_each { |account| account.transition_to!(:active, installation_id: "12345") }
      Account.update_all(current_state: nil)

      UpdateConfig.find_each { |update_config| update_config.transition_to!(:rate_limited) }
      UpdateConfig.update_all(current_state: nil)

      UpdateJob.find_each { |update_job| update_job.transition_to!(:enqueued) }
      UpdateJob.update_all(current_state: nil)

      PullRequest.find_each { |pull_request| pull_request.transition_to!(:closed) }
      PullRequest.update_all(current_state: nil)

      PendingPullRequest.find_each { |pending_pull_request| pending_pull_request.transition_to!(:created) }
      PendingPullRequest.update_all(current_state: nil)

      expect(Account.where(current_state: "active").count).to be 0
      expect(UpdateConfig.where(current_state: "rate_limited").count).to be 0
      expect(UpdateJob.where(current_state: "enqueued").count).to be 0
      expect(PullRequest.where(current_state: "closed").count).to be 0
      expect(PendingPullRequest.where(current_state: "created").count).to be 0

      transition.perform

      expect(Account.where(current_state: "active").count).to be 2
      expect(UpdateConfig.where(current_state: "rate_limited").count).to be 2
      expect(UpdateJob.where(current_state: "enqueued").count).to be 2
      expect(PullRequest.where(current_state: "closed").count).to be 2
      expect(PendingPullRequest.where(current_state: "created").count).to be 2
    end

    it "skips records that already have a current_state" do
      expect(Account.where(current_state: "inactive").count).to be 2
      expect(UpdateConfig.where(current_state: "pending").count).to be 2
      expect(UpdateJob.where(current_state: "pending").count).to be 2
      expect(PullRequest.where(current_state: "up_to_date").count).to be 2
      expect(PendingPullRequest.where(current_state: "pending").count).to be 2

      expect { transition.perform }.not_to(change do
        Account.where(current_state: "inactive").count +
          UpdateConfig.where(current_state: "pending").count +
          UpdateJob.where(current_state: "pending").count +
          PullRequest.where(current_state: "up_to_date").count +
          PendingPullRequest.where(current_state: "pending").count
      end)
    end

    it "skips records that are transitioned between reading and writing" do
      # set all records to nil in the DB to simulate missing current_state
      Account.update_all(current_state: nil)

      # simulate a record being transitioned while the backfill is running
      account_to_transition = Account.first
      race_condition_aware_transition = transition
      allow(race_condition_aware_transition).
        to receive(:update_with_retries).
        and_wrap_original do |original_method, *args|
          account_to_transition.transition_to!(:active, installation_id: "67890")
          original_method.call(*args)
        end

      race_condition_aware_transition.perform

      expect(Account.where(current_state: AccountStateMachine.initial_state).count).to be 1
    end

    it "fetches records in batches" do
      # set all records to nil in the DB to simulate missing current_state
      Account.update_all(current_state: nil)
      UpdateConfig.update_all(current_state: nil)
      UpdateJob.update_all(current_state: nil)
      PullRequest.update_all(current_state: nil)
      PendingPullRequest.update_all(current_state: nil)

      batched_transition = transition(read_batch_size: 1)
      expect(batched_transition).
        to receive(:update_with_retries).
        with(instance_of(Class), instance_of(Array), instance_of(String)).
        and_call_original.
        exactly(10).times

      batched_transition.perform
    end

    it "writes records in batches" do
      # set all records to nil in the DB to simulate missing current_state
      Account.update_all(current_state: nil)
      UpdateConfig.update_all(current_state: nil)
      UpdateJob.update_all(current_state: nil)
      PullRequest.update_all(current_state: nil)
      PendingPullRequest.update_all(current_state: nil)

      transition(write_batch_size: 1).perform
      expect(freno_throttler).to have_received(:throttle).exactly(10).times
    end

    it "retries freno failures" do
      Account.update_all(current_state: nil)

      error = Freno::Throttler::WaitedTooLong.new
      expect(freno_throttler).
        to receive(:throttle).
        and_raise(error).
        exactly(Dependabot::Transitions::BackfillCurrentStateValues::RETRY_COUNT + 1).times

      retry_wait = 0.001 # 1ms
      expect do
        transition(retry_wait: retry_wait).process_type(Account, AccountTransition, AccountStateMachine)
      end.to raise_error(Freno::Throttler::WaitedTooLong)
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      Account.update_all(current_state: nil)
      UpdateConfig.update_all(current_state: nil)
      UpdateJob.update_all(current_state: nil)
      PullRequest.update_all(current_state: nil)
      PendingPullRequest.update_all(current_state: nil)

      expect { transition(dry_run: true).perform }.not_to(change do
        Account.where(current_state: AccountStateMachine.initial_state).count +
          UpdateConfig.where(current_state: UpdateConfigStateMachine.initial_state).count +
          UpdateJob.where(current_state: UpdateJobStateMachine.initial_state).count +
          PullRequest.where(current_state: PullRequestStateMachine.initial_state).count +
          PendingPullRequest.where(current_state: PendingPullRequestStateMachine.initial_state).count
      end)
    end
  end
end
