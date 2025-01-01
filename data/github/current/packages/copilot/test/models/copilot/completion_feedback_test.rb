# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotCompletionFeedbackTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @user = create(:user)
  end

  setup do
    @job_status = Copilot::CompletionJobStatus.create \
      repository: @repo,
      actor: @user,
      context: { foo: "bar" }
  end

  context ".for_job" do
    test "buids new feedback object if one doesn't exist" do
      feedback = Copilot::CompletionFeedback.for_job(@job_status.id)

      assert_equal @repo, feedback.repository
      assert_equal @user, feedback.user
      assert_equal @job_status.id, feedback.job_id
      assert_equal "bar", feedback.context[:foo]
    end

    test "finds existing feedback for the job if it exists" do
      existing = Copilot::CompletionFeedback.for_job(@job_status.id)
      existing.save!

      assert_equal existing, Copilot::CompletionFeedback.for_job(@job_status.id)
    end
  end

  context ".for_text_completion_session" do
    test "builds new feedback object if one doesn't exist" do
      session_id = SecureRandom.uuid
      Codespaces::Kv.store.set("completion_feedback_#{@user.id}_#{@repo.id}", session_id)
      feedback = Copilot::CompletionFeedback.for_text_completion_session(@user.id, @repo.id, session_id, nil)

      assert_equal @repo.id, feedback&.repository_id
      assert_equal @user.id, feedback&.user_id
      assert_equal session_id, feedback&.session_id
      assert_equal({ actor_id: @user.id, repository_id: @repo.id, session_id: }, feedback&.context)
    end

    test "finds existing feedback for the session if it exists" do
      session_id = SecureRandom.uuid
      Codespaces::Kv.store.set("completion_feedback_#{@user.id}_#{@repo.id}", session_id)
      existing = Copilot::CompletionFeedback.for_text_completion_session(@user.id, @repo.id, session_id, nil)
      existing&.save!

      assert existing
      assert_equal existing, Copilot::CompletionFeedback.for_text_completion_session(@user.id, @repo.id, session_id, nil)
    end

    test "applies session context to existing feedback for a summary job" do
      existing = Copilot::CompletionFeedback.for_job(@job_status.id)
      existing.save!

      session_id = SecureRandom.uuid
      Codespaces::Kv.store.set("completion_feedback_#{@user.id}_#{@repo.id}", session_id)
      feedback = Copilot::CompletionFeedback.for_text_completion_session(@user.id, @repo.id, session_id, @job_status.id)

      assert_equal @job_status.id, feedback&.job_id
      assert_equal session_id, feedback&.session_id
      assert_equal session_id, (feedback&.context || {})[:session_id]

      expected_subset_context = { session_id:, foo: "bar" }
      assert_equal expected_subset_context, (feedback&.context || {}).slice(:session_id, :foo)
    end

    test "applies job context to existing feedback for a session" do
      session_id = SecureRandom.uuid
      Codespaces::Kv.store.set("completion_feedback_#{@user.id}_#{@repo.id}", session_id)
      existing = Copilot::CompletionFeedback.for_text_completion_session(@user.id, @repo.id, session_id, nil)
      existing&.save!

      feedback = Copilot::CompletionFeedback.for_text_completion_session(@user.id, @repo.id, session_id, @job_status.id)

      assert_equal @job_status.id, feedback&.job_id
      assert_equal session_id, feedback&.session_id
      assert_equal session_id, (feedback&.context || {})[:session_id]

      expected_subset_context = { session_id:, foo: "bar" }
      assert_equal expected_subset_context, (feedback&.context || {}).slice(:session_id, :foo)
    end
  end
end
