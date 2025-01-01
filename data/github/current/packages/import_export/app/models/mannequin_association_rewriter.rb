# typed: true
# frozen_string_literal: true

class MannequinAssociationRewriter
  TRANSFERABLE_ASSOCIATIONS = [
    :commit_comments,
    :created_projects,
    :issue_comments,
    :issues,
    :project_cards,
    :projects,
    :pull_request_review_comments,
    :pull_request_reviews,
    :pull_requests,
    :release_mentions,
    :releases,
    :review_requests,
    :subjected_issue_event_details,
  ].freeze

  attr_reader :source, :target

  def initialize(source, target)
    @source = source
    @target = target
  end

  def rewrite!
    TRANSFERABLE_ASSOCIATIONS.each do |association|
      source.send(association).transfer_to(target)
    end

    Assignments::Public.transfer_to_assignee(source, target)
    Attachments::Public.transfer_to_attacher(source.id, target.id)
    CrossReferences::Public.transfer_to_actor(source.id, target.id)
    IssueEvents::Public.transfer_to_actor(source.id, target.id)
  end
end
