# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# AnnotationCreator is used by CreateCodeScanningAnnotationsJob
# to create Pull Request annotations
class CodeScanning::AnnotationCreator
  BATCH_SIZE = 25

  sig { params(check_run: CheckRun, new_alerts: T::Array[Turboscan::Proto::DiffedAlert]).returns(Integer) }
  def create_annotations(check_run, new_alerts)
    return 0 if new_alerts.empty?

    alert_numbers = {}
    CodeScanningAnnotation.where(repository_id: check_run.repository_id, check_annotation: check_run.annotations)
                    .in_batches { |batch| alert_numbers.merge!(batch.pluck(:check_annotation_id, :alert_number).to_h) }
    annotations_by_number = check_run.annotations.group_by { |annotation| alert_numbers[annotation.id] }

    # We're sorting alerts by decreasing severity so that we create annotations for more severe alerts first.
    # This causes the most severe alerts to show up first in lists like on the summary page and the review of the advanced security bot.
    new_alerts.sort_by! { |alert| CheckAnnotation.warning_level_to_i(CheckAnnotation.annotation_level_for_code_scanning_annotation(alert.security_severity, alert.rule_severity)) }

    new_annotations_count = 0
    new_alerts.each_slice(BATCH_SIZE) do |alerts_slice|
      alerts_slice.each do |alert|
        annotations = annotations_by_number[alert.number]
        next if annotations.present? && annotation_exists_for_location?(annotations, alert.location)
        create_annotation(check_run, alert)
        new_annotations_count += 1
      end
    end

    new_annotations_count
  end

  private

  def create_annotation(check_run, alert)
    location_attributes = annotation_attributes(alert.location)

    attributes = location_attributes.merge({
      annotation_level: CheckAnnotation.annotation_level_for_code_scanning_annotation(alert.security_severity, alert.rule_severity),
      message: alert.message_text.presence || "-",
      title: alert.rule_short_description,
      repository: check_run.repository,
      code_scanning_annotation_attributes: {
        alert_number: alert.number,
        repository: check_run.repository,
        check_run: check_run,
      }
    })

    ActiveRecord::Base.connected_to(role: :writing) do
      check_run.annotations.create!(attributes)
    end
  end

  # Does an annotation already exist for the given alert location?
  #
  # Return true if an annotation already has been created for the alert location,
  # false otherwise.
  def annotation_exists_for_location?(annotations, location)
    location_attributes = annotation_attributes(location)

    annotations.any? do |annotation|
      same_start_and_end_lines?(annotation, location_attributes) &&
      same_start_and_end_columns?(annotation, location_attributes)
    end
  end

  def same_start_and_end_lines?(annotation, location_attributes)
    annotation.start_line == location_attributes[:start_line] &&
    annotation.end_line == location_attributes[:end_line]
  end

  def same_start_and_end_columns?(annotation, location_attributes)
    start_columns_match?(annotation, location_attributes) &&
    end_columns_match?(annotation, location_attributes)
  end

  def start_columns_match?(annotation, location_attributes)
    # If the location doesn't specify a column, it counts as a match
    return true unless location_attributes.has_key?(:start_column)

    annotation.start_column == location_attributes[:start_column]
  end

  def end_columns_match?(annotation, location_attributes)
    # If the location doesn't specify a column, it counts as a match
    return true unless location_attributes.has_key?(:end_column)

    annotation.end_column == location_attributes[:end_column]
  end

  def annotation_attributes(location)
    location_attributes = {
      path: location.file_path,
      start_line: zero_bad_line_locations(location.start_line),
      end_line: zero_bad_line_locations(location.end_line),
    }

    # Check annotations can only have start/end columns when the annotation
    # does not span multiple lines
    start_column = zero_bad_line_locations(location.start_column)
    end_column = zero_bad_line_locations(location.end_column)
    if location_attributes[:start_line] == location_attributes[:end_line] && start_column > 0
      location_attributes[:start_column] = start_column
      # Use start column when end column is missing
      location_attributes[:end_column] = end_column.zero? ? start_column : end_column
    end

    location_attributes
  end

  def zero_bad_line_locations(number)
    # Sets line locations larger than 32bit max int or negative numbers to zero

    # This is a workaround for bad tool inputs giving line numbers like -1 which the go code uint overflows
    # and which the database fails to store as a 32bit int.
    # No real user input should ever have a negative line / column number or one of this magnitude.
    maximum = 2**31 - 1
    return 0 if number > maximum || number < 0
    number
  end
end
