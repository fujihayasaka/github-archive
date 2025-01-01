# typed: true
# frozen_string_literal: true

class Issue::Adapter::CrossReferencedEventAdapter < Issue::Adapter::TimelineEventAdapter
  attr_reader :actor
  attr_reader :created_at
  attr_reader :database_id
  attr_reader :id

  # CrossReference
  attr_reader :referenced_at
  attr_reader :is_cross_repository
  attr_reader :resource_path
  attr_reader :source
  attr_reader :target

  CROSS_REFERENCED_EVENT = "CrossReferencedEvent"

  TYPES = [
    PlatformTypes::CrossReferencedEvent,
  ].freeze

  def initialize(context, event_id:)
    super(context)

    @database_id = event_id
    @cross_reference = context.cross_references_by_id[event_id]
    @id = @cross_reference.global_relay_id
    @actor = @cross_reference.actor
    @created_at = @cross_reference.created_at
    @referenced_at = @cross_reference.referenced_at
    @is_cross_repository = @cross_reference.cross_repository?

    # the platform cross reference event resource path is defined via metaprogramming in
    #   app/platform/helpers/url.rb
    # via
    #   url_fields description: "The HTTP URL for this pull request." do |cross_ref_event|
    #     cross_ref_event.async_path_uri
    #   end
    # in app/platform/objects/cross_referenced_event.rb
    @resource_path = resource_path_for(@cross_reference.path_uri)

    source = @cross_reference.source_issue_or_pull_request

    @source = if source.is_a?(Issue)
      Issue::Adapter::CrossReferenceSourceIssueAdapter.new(@context, issue: source)
    elsif source.is_a?(PullRequest)
      Issue::Adapter::CrossReferenceSourcePullRequestAdapter.new(@context, pull_request: source)
    elsif source.nil?
      nil
    else
      raise "Unsupported source type"
    end

    # If source is nil, it is invalid and don't need to process the target.
    unless @source.nil?
      target = @cross_reference.target_issue_or_pull_request
      @target = if target.is_a?(Issue)
        Issue::Adapter::CrossReferenceTargetIssueAdapter.new(@context, issue: target)
      elsif target.is_a?(PullRequest)
        Issue::Adapter::CrossReferenceTargetPullRequestAdapter.new(@context, pull_request: target)
      elsif target.nil?
        nil
      else
        raise "Unsupported target type"
      end
    end

    # If source or the target is nil, then this is an invalid cross reference.
    @invalid = @source.nil? || @target.nil?
  end

  # app/views/issues/events/_cross_reference.html.erb:78
  def is_cross_repository?
    @is_cross_repository
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
