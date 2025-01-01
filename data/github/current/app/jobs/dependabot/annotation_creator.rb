# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# AnnotationCreator is used by CreateDependabotAnnotationsJob
# to create Pull Request annotations
class Dependabot::AnnotationCreator

  # Create annotations from parsed Dependabot SARIF
  # Return the count of new annotations created
  def create_annotations(check_run, annotation_attributes)
    return 0 if annotation_attributes.nil?

    # Fetch existing annotations for the check run to avoid duplication
    existing_annotations = fetch_existing_annotations(check_run)
    annotations_by_autofix_job_id = existing_annotations.group_by { |annotation| annotation.autofix_job_id }

    # Skip if an annotation for this logical ID already exists
    existing_annotations_for_autofix_job_id = annotations_by_autofix_job_id[annotation_attributes[:autofix_job_id]]
    if existing_annotations_for_autofix_job_id.present? && annotation_exists_for_location?(existing_annotations_for_autofix_job_id, annotation_attributes[:locations])
      return 0
    end

    # Create the new annotation for the annotation_attributes
    create_annotation(check_run, annotation_attributes)

    # Return the count of new annotations created (always 1 in this case)
    1
  end

  # Fetch existing annotations for this check run to prevent creating duplicates
  def fetch_existing_annotations(check_run)
    # TODO - this is a temporary solution to fetch existing annotations
    # DependabotAnnotation.where(repository_id: check_run.repository_id, check_run_id: check_run.id)
    []
  end

  private

  # Create an annotation for the given SARIF entry
  def create_annotation(check_run, annotation_attributes)
    location_attributes = annotation_attributes(annotation_attributes[:locations].first)

    attributes = location_attributes.merge({
      annotation_level: annotation_attributes[:level],
      message: annotation_attributes[:message],
      title: "Breaking change detected",
      repository: check_run.repository,
      dependabot_annotation_attributes: {
        autofix_job_id: annotation_attributes[:autofix_job_id],
        repository: check_run.repository,
        check_run: check_run,
      }
    })

    ActiveRecord::Base.connected_to(role: :writing) do
      check_run.annotations.create!(attributes)
    end
  end

  # Check if an annotation already exists for the given location
  def annotation_exists_for_location?(annotations, location)
    location_attributes = annotation_attributes(location)

    annotations.any? do |annotation|
      same_start_and_end_lines?(annotation, location_attributes) &&
      same_start_and_end_columns?(annotation, location_attributes)
    end
  end

  # Check if start and end lines match
  def same_start_and_end_lines?(annotation, location_attributes)
    annotation.start_line == location_attributes[:start_line] &&
    annotation.end_line == location_attributes[:end_line]
  end

  # Check if start and end columns match
  def same_start_and_end_columns?(annotation, location_attributes)
    start_columns_match?(annotation, location_attributes) &&
    end_columns_match?(annotation, location_attributes)
  end

  # Check start column match
  def start_columns_match?(annotation, location_attributes)
    return true unless location_attributes.has_key?(:start_column)
    annotation.start_column == location_attributes[:start_column]
  end

  # Check end column match
  def end_columns_match?(annotation, location_attributes)
    return true unless location_attributes.has_key?(:end_column)
    annotation.end_column == location_attributes[:end_column]
  end

  # Set annotation attributes based on the manifest file dependency update location
  def annotation_attributes(location)
    location_attributes = {
      path: location[:artifactLocation],
      start_line: zero_bad_line_locations(location[:startLine]),
      end_line: zero_bad_line_locations(location[:endLine]),
    }

    start_column = zero_bad_line_locations(location[:startColumn])
    end_column = zero_bad_line_locations(location[:endColumn])
    if location_attributes[:start_line] == location_attributes[:end_line] && start_column > 0
      location_attributes[:start_column] = start_column
      location_attributes[:end_column] = end_column.zero? ? start_column : end_column
    end

    location_attributes
  end

  # Normalize bad line locations
  def zero_bad_line_locations(number)
    maximum = 2**31 - 1
    return 0 if number > maximum || number < 0
    number
  end
end
