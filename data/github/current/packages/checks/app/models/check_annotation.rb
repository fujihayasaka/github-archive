# typed: true
# frozen_string_literal: true

class CheckAnnotation < ApplicationRecord::Domain::RepositoriesActionsChecks
  include GitHub::UTF8
  include GitHub::FieldTruncator
  include GitHub::Validations
  include CheckAnnotation::ActionsDependency

  attribute :message, Checks::MaybeCompressed.new(self, :message)
  attribute :filename, StringFromBinary.new

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  belongs_to :check_run, inverse_of: :annotations
  belongs_to :check_suite, inverse_of: :annotations

  has_one :code_scanning_annotation, ->(check_annotation) { where(repository_id: check_annotation.repository_id) }, dependent: :destroy
  accepts_nested_attributes_for :code_scanning_annotation

  has_one :dependabot_annotation, ->(check_annotation) { where(repository_id: check_annotation.repository_id) }, dependent: :destroy
  accepts_nested_attributes_for :dependabot_annotation

  alias_attribute :path, :filename
  alias_attribute :annotation_level, :warning_level

  validates_presence_of :path
  validates_presence_of :start_line
  validates_presence_of :end_line
  validates_presence_of :annotation_level
  validates_presence_of :message
  validates :raw_details, unicode3: true
  validate :matches_check_suite_repository
  validate :matches_check_run_repository

  validate :range_validation

  before_save :truncate_fields

  MAX_PER_REQUEST = 25

  MAX_READ_LIMIT = 1_000

  LINE_PADDING = 3

  MAX_VARBINARY_FIELD_LENGTH = 1024
  MAX_BLOB_OR_TEXT_FIELD_LENGTH = 65535

  # For annotations created by orchestration or other actions backend services, this is used as a placeholder for the
  # path that is required by existing constraints. e.g. this can correspond to error, warning or notice commands in
  # @actions/toolkit, the runner itself or a backend service like actions-results.
  ACTIONS_SYSTEM_PATH = ".github"

  # In terms of importance, failures are the most important, followed by warnings, and then notices.
  WARNING_LEVEL_SORT = { "failure" => 0, "warning" => 1, "notice" => 2 }

  # There should only be 3 types of annotations, however it appears that users are somehow creating annotations with other types of warning levels such as "success"
  # If we encounter an unknown warning level, we will default to 3 which is the lowest priority.
  def self.warning_level_to_i(warning_level)
    WARNING_LEVEL_SORT[warning_level] || 3
  end

  def warning_level_to_i
    self.class.warning_level_to_i(warning_level)
  end

  def github_app
    check_suite = self.check_suite
    check_suite.present? ? check_suite.github_app : T.must(check_run).github_app
  end

  def title
    utf8(super || default_title)
  end

  def parent_name
    check_suite = self.check_suite
    check_suite.present? ? check_suite.workflow_name : T.must(check_run).visible_name
  end

  def parent_type
    return "workflow run" if check_suite&.workflow_run.present?
    return "check suite" if check_suite.present?
    return "workflow job" if check_run&.workflow_job_run.present?

    "check run"
  end

  def blob_href
    run = T.must(check_run)
    "#{GitHub.url}/#{T.must(run.repository).name_with_display_owner}/blob/#{run.head_sha}/#{path}"
  end

  def range_validation
    # not currently enforcing that both start_column and end_column need to be set,
    # see https://github.com/github/c2c-actions-checks/issues/319#issuecomment-1142307957
    start_column = self.start_column
    end_column = self.end_column

    if start_line.present? && end_line.present?
      if start_line > end_line
        errors.add(:start_line, "must be less than or equal to `end_line`")
      end

      if end_line < start_line
        errors.add(:end_line, "must be greater than or equal to `start_line`")
      end

      if start_column.present?
        if !same_line?
          errors.add(:start_column, "can't be provided across multiple lines")
        end
        if end_column.present? && start_column > end_column
          errors.add(:start_column, "must be less than or equal to `end_column`")
        end
      end

      if end_column.present?
        if !same_line?
          errors.add(:end_column, "can't be provided across multiple lines")
        end
        if start_column.present? && end_column < start_column
          errors.add(:end_column, "must be greater than or equal to `start_column`")
        end
      end
    end
  end

  def line_range
    (start_line - LINE_PADDING)..(end_line + LINE_PADDING)
  end

  def default_title?
    title == default_title
  end

  def error?
    warning_level == "failure"
  end

  def warning?
    warning_level == "warning"
  end

  def notice?
    warning_level == "notice"
  end

  def parsed_file_name
    annotation_check_suite = check_suite.present? ? check_suite : check_run&.check_suite
    return filename unless annotation_check_suite&.required_workflow?

    parse_and_format_required_workflow_filename if annotation_check_suite.required_workflow?
  end

  def self.annotation_level_for_code_scanning_annotation(security_severity, rule_severity)
    if security_severity.present? &&
      security_severity != :NO_SECURITY_SEVERITY

      case security_severity
      when :CRITICAL, :HIGH
        return "failure"
      when :MEDIUM
        return "warning"
      else
        return "notice"
      end
    end

    case rule_severity
    when :ERROR
      "failure"
    when :WARNING
      "warning"
    else
      "notice"
    end
  end

  def system_path?
    path == ACTIONS_SYSTEM_PATH
  end

  private

  def matches_check_suite_repository
    check_suite = self.check_suite
    if check_suite && repository_id && repository_id != check_suite.repository_id
      errors.add(:repository, "does not match the check suite's repository")
    end
  end

  def matches_check_run_repository
    check_run = self.check_run
    if check_run && repository_id && repository_id != check_run.repository_id
      errors.add(:repository, "does not match the check run's repository")
    end
  end

  def default_title
    line_format = [start_line, end_line].uniq.map { |line| "L#{line}" }.join("-")
    "#{filename}##{line_format}"
  end

  def same_line?
    (end_line - start_line).zero?
  end

  def truncate_fields
    truncate_field(:filename, MAX_VARBINARY_FIELD_LENGTH)
    truncate_field(:title, MAX_VARBINARY_FIELD_LENGTH)
    truncate_field(:raw_details, MAX_BLOB_OR_TEXT_FIELD_LENGTH)
    truncate_field(:message, MAX_BLOB_OR_TEXT_FIELD_LENGTH)
  end
end
