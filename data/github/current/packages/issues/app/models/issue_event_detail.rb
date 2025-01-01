# typed: true
# frozen_string_literal: true

# Replaces serialized attributes from IssueEvent records
# Because the issue_event_details table can represent several types of
# IssueEvent, many of its fields may be null.
class IssueEventDetail < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Validations
  include Issue::StateReasonDependency

  belongs_to :issue_event
  belongs_to :subject, polymorphic: true

  alias_method :raw_subject, :subject
  alias_method :raw_subject=, :subject=

  attr_reader :label

  attribute :milestone_title, StringFromBinary.new
  attribute :title_is, StringFromBinary.new
  attribute :title_was, StringFromBinary.new
  attribute :message, StringFromBinary.new
  attribute :column_name, StringFromBinary.new
  attribute :previous_column_name, StringFromBinary.new
  attribute :label_name, StringFromBinary.new

  # VARBINARY limit from the database
  UTF8_BYTESIZE_LIMIT = 1024

  validates :milestone_title, unicode: true, bytesize: { maximum: UTF8_BYTESIZE_LIMIT }
  validates :title_is, unicode: true, bytesize: { maximum: UTF8_BYTESIZE_LIMIT }
  validates :title_was, unicode: true, bytesize: { maximum: UTF8_BYTESIZE_LIMIT }
  validates :message, unicode: true, length: { maximum: 1000 }
  validates :repository_id, presence: true, on: :create

  before_validation :set_repository_id, on: :create
  before_save :truncate_ref_utf8 # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Public: set the label attributes
  #
  # label: A Label
  def label=(label)
    self.label_id         = label.id
    self.label_name       = label.name
    self.label_color      = label.color
    self.label_text_color = label.text_color
    @label                = label
  end

  # Public: set the subject
  #
  # Note: In case of the `assigned` and `unassigned` events, the subject field stores the actor
  # and the actor field stores the subject (the user being assigned/unassigned in this case).
  # Yes, that's not how we usually use these fields but it's virtually impossible to change it now.
  #
  # assigned_subject: a User, Issue, Bot, Project, or Team
  def subject=(assigned_subject)
    self.raw_subject = @subject = assigned_subject
  end

  # Public: Return the subject
  #
  # Returns a User, Issue, Bot, Project, or Team
  def subject
    @subject ||= if subject_type
      if subject_type == "PRReviewPoint"
        PullRequestReviewPoint.find_by(id: subject_id)
      else
        self.raw_subject
      end
    elsif subject_id
      User.find_by id: subject_id
    end
  end

  def async_subject
    return Promise.resolve(subject) if association(:subject).loaded?

    type = case
    when subject_type == "PRReviewPoint"
      ::PullRequestReviewPoint
    when subject_type
      T.must(subject_type).constantize
    else
      ::User
    end

    Platform::Loaders::ActiveRecord.load(type, subject_id)
  end

  def truncate_ref_utf8
    return unless ref = self.ref
    # identify first 4-byte character
    posn = ref.chars.index { |c| c.bytes.count >= 4 }
    truncate_to = posn ? [posn - 1, 254].min : 254
    self.ref = ref[0..truncate_to]
  end

  private def set_repository_id
    self.repository_id = issue_event&.repository_id
  end
end
