# typed: true
# frozen_string_literal: true

class UserHovercard
  attr_reader :user

  # In order to keep the hierarchy from getting out of control, put a practical
  # upper bound on the number of jumps upward we can do
  MAX_SUBJECT_DEPTH = 5

  def initialize(user, primary_subject, viewer:)
    @user = user
    @primary_subject = primary_subject
    @viewer = viewer
  end

  # Return each of the contexts in which this user should be considered
  # in this hovercard.  One for each relevant subject plus the global context.
  def contexts
    ActiveRecord::Base.connected_to(role: :reading) do
      contexts = subject_hierarchy.flat_map.with_index do |subject, idx|
        subject.async_user_hovercard_contexts_for(@user, viewer: @viewer,
          descendant_subjects: subject_hierarchy.first(idx + 1))
      end

      contexts.concat global_subject.async_user_hovercard_contexts_for(@user, viewer: @viewer,
        descendant_subjects: subject_hierarchy)

      Promise.all(contexts.compact).sync.compact
    end
  end

  # An array of contexts upwards from the primary_subject
  def subject_hierarchy
    lazy_subjects = subject_enumerable.lazy.take_while do |subject|
      viewer_can_view?(subject)
    end
    lazy_subjects.first(MAX_SUBJECT_DEPTH)
  end

  # The containing organization for the subject (if any)
  def subject_organization
    subject_hierarchy.detect { |s| s.is_a?(Organization) }
  end

  # Used by Platform::Objects::Hovercard
  def model
    user
  end

  def platform_type_name
    "Hovercard"
  end

  private

  def global_subject
    UserHovercard::GlobalSubject.new
  end

  def viewer_can_view?(subject)
    subject_type = Platform::Helpers::NodeIdentification.type_name_from_object(subject)
    viewer_abilities.typed_can_see?(subject_type, subject).sync
  end

  def viewer_abilities
    return @viewer_abilities if @viewer_abilities

    @viewer_abilities = Platform::Authorization::Permission.new(viewer: @viewer, origin: Platform::ORIGIN_INTERNAL)
  end

  # Return an Enumerator that returns subjects in order up the hierarchy
  def subject_enumerable
    subject = @primary_subject

    Enumerator.new do |y|
      until subject.nil?
        y << subject
        subject = subject.user_hovercard_parent
      end
    end
  end
end
