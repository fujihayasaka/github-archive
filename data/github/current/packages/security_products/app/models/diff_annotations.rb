# typed: true
# frozen_string_literal: true

class DiffAnnotations
  include Enumerable

  def initialize(annotations, diffs = nil, code_scanning_alerts: {}, dependabot_annotations: {})
    @annotations = annotations
    @diffs = diffs

    if @diffs.present?
      @diff_paths = encoded_diff_paths
    end

    # only keep code scanning alerts that correspond to an annotation
    @code_scanning_annotations = @annotations.map do |annotation|
      [annotation.id, code_scanning_alerts[annotation.id]]
    end.to_h.compact
    @dependabot_annotations = @annotations.map do |annotation|
      [annotation.id, dependabot_annotations[annotation.id]]
    end.to_h.compact
  end

  # Retrieve the, possibly empty, collection of annotations for this path name.
  #
  # Returns a DiffAnnotations collection.
  def path(path)
    DiffAnnotations.new(paths[path] || [],
      code_scanning_alerts: @code_scanning_annotations,
      dependabot_annotations: @dependabot_annotations,
    )
  end

  # Retrieve the, possibly empty, collection of annotations with end_lines at this line number.
  #
  # Returns a DiffAnnotations collection.
  def end_line(line)
    DiffAnnotations.new(end_lines[line] || [],
      code_scanning_alerts: @code_scanning_annotations,
      dependabot_annotations: @dependabot_annotations,
    )
  end

  # Filters out annotations with comments
  def annotations_without_comments(pull_request)
    # pull_request can be nil if this is called from a non-PR commit page
    annotations = if pull_request.present?
      alert_numbers_with_comments = pull_request.code_scanning_review_comments.pluck(:alert_number).to_set

      reject do |annotation|
        alert = code_scanning_alert(annotation)
        if alert.present? && alert_numbers_with_comments.include?(alert[:cs_annotation].alert_number)
          true
        else
          dependabot_annotation(annotation)&.present?
        end
      end
    else
      to_a
    end

    DiffAnnotations.new(annotations,
      code_scanning_alerts: @code_scanning_annotations,
      dependabot_annotations: @dependabot_annotations,
    )
  end

  # Fetch dependabot_annotation for a given annotation, leveraging the preloaded hash
  def dependabot_annotation(annotation)
    @dependabot_annotations[annotation.id]
  end

  def load_dependabot_annotations(viewer:, pull_request:)
    return unless pull_request

    # Fetch all relevant check annotations in one query
    check_annotations = DependabotAnnotation.where(
      repository_id: pull_request.repository.id,
      check_annotation_id: @annotations.map(&:id)
    )

    # Build a hash to map annotation IDs to their respective check_annotation
    @dependabot_annotations = check_annotations.index_by(&:check_annotation_id)
    nil
  end

  # Iterate through each Annotation in the collection.
  #
  # Returns an Enumerator.
  def each(&block)
    @annotations.each(&block)
  end

  # Returns an Array of Strings representing filepaths
  def non_diff_paths
    non_diff.pluck(:path).uniq
  end

  # Returns a hash of (key) file_path and (value) Array of context line
  # ranges that we want to render in order to display annotations, even if
  # they are not actually part of the diff.
  #
  # {
  #   "file_path": [2..8, 28..38]
  # }
  def line_ranges
    paths.map do |path, annotations|
      line_ranges = annotations.map(&:line_range)

      [path, line_ranges]
    end.to_h
  end

  # Attempt to retrieve a code scanning alert for an annotation from this
  # DiffAnnotations object. This may return nil if the annotation is not a code
  # scanning alert, or load_code_scanning_alerts has not been called.
  # This method returns a hash with keys :cs_annotation, :result and :refs
  # where cs_annotation should always be present unless the result of this method is nil
  def code_scanning_alert(annotation)
    @code_scanning_annotations[annotation.id]
  end

  # Load additional data for rendering annotations that are code scanning
  # alerts.
  def load_code_scanning_alerts(viewer:, repository:)
    return unless repository&.show_code_scanning_annotations_ui?(viewer)

    @code_scanning_annotations = CodeScanningAnnotation.results_by_id(
      repository: repository,
      annotations: @annotations.map(&:id)
    )
    nil
  end

  private

  def paths
    @paths ||= @annotations.group_by { |annotation| annotation.path }
  end

  def end_lines
    @end_lines ||= @annotations.group_by { |annotation| annotation.end_line }
  end

  def non_diff
    return [] unless @diff_paths.present?
    @non_diff ||= @annotations.reject { |annotation| @diff_paths.include?(annotation.path) }
  end

  def encoded_diff_paths
    @diffs.requested_paths.map { |path| GitHub::Encoding.try_guess_and_transcode(path) }
  end
end
