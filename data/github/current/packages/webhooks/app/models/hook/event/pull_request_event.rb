# typed: true
# frozen_string_literal: true

class Hook::Event::PullRequestEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  def self.description(desc = nil)
    actions = [
      :assigned,
      :auto_merge_disabled,
      :auto_merge_enabled,
      :closed,
      :converted_to_draft,
      :demilestoned,
      :dequeued,
      :edited,
      :enqueued,
      :labeled,
      :locked,
      :milestoned,
      :opened,
      :ready_for_review,
      :reopened,
      :review_request_removed,
      :review_requested,
      :synchronized,
      :unassigned,
      :unlabeled,
      :unlocked,
    ]

    actions.map! { |action|  action.to_s.humanize(capitalize: false) }
    @description = "Pull request #{actions.to_sentence(last_word_connector: ", or ")}."
  end

  event_attr :action, :pull_request_id, required: true
  event_attr :actor_id, :label_id, :assignee_id, :subject_id, :subject_type, :changes, :before, :after, :reason, :milestone_id

  def initialize_primary_resource
    return unless primary_resource_data&.is_a?(Hash)
    # explicit column filtering to ensure even model is resilient to migrations and database changes
    # https://github.com/github/availability/issues/2669
    valid_keys = PullRequest.column_names
    primary_resource_data.filter! do |key|
      valid_keys.any? { |valid_key| key.to_s == valid_key }
    end
    @pull_request = PullRequest.new(primary_resource_data)
  end

  def pull_request
    @pull_request ||= PullRequest.find_by(id: pull_request_id)
  end

  def target_repository
    @target_repository ||= pull_request.try(:repository)
  end

  def actor
    @actor ||= User.find_by(id: actor_id) || pull_request.try(:user)
  end

  # The label which was labeled/unlabeled
  def label
    return @label if defined?(@label)

    @label = Label.find_by(id: label_id)
  end

  # The user or team which was review_requested/review_request_removed
  def requested_reviewer
    return @requested_reviewer if defined?(@requested_reviewer)

    if subject_type == "Team"
      @requested_reviewer = Team.find_by(id: subject_id)
    else
      @requested_reviewer = User.find_by(id: subject_id)
    end
  end

  # The user which was assigned/unassigned
  def assignee
    return @assignee if defined?(@assignee)

    @assignee = User.find_by(id: assignee_id)
  end

  # The milestone which was milestoned/demilestoned
  def milestone
    return @milestone if defined?(@milestone)

    @milestone = Milestone.find_by(id: milestone_id)
  end

  def changes
    return unless changes_attr

    {}.tap do |changes_hash|
      changes_hash[:body] = { from: changes_attr[:old_body] } if body_changes?
      changes_hash[:title] = { from: changes_attr[:old_title] } if title_changes?

      changes_hash[:base] = {} if base_ref_changes? || base_sha_changes?
      changes_hash[:base][:ref] = { from: changes_attr[:old_base_ref] } if base_ref_changes?
      changes_hash[:base][:sha] = { from: changes_attr[:old_base_sha] } if base_sha_changes?
    end
  end

  def deliverable?
    target_repository.present?
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def body_changes?
    changes_attr[:old_body]
  end

  def title_changes?
    changes_attr[:old_title] && changes_attr[:title]
  end

  def base_ref_changes?
    changes_attr[:old_base_ref] && changes_attr[:base_ref]
  end

  def base_sha_changes?
    changes_attr[:old_base_sha] && changes_attr[:base_sha]
  end
end
