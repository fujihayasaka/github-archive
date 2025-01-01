# typed: true
# frozen_string_literal: true

class Checks::CreateCheckAnnotations
  include GitHub::Tracing

  STATS_PREFIX = "checks/create_check_annotations"

  attr_reader :check_suite, :annotations

  trace_method(
    :call,
    span_attribute_extractor: -> (instance, *_args, **_kwargs) do
      {
        "gh.repo.id" => instance.check_suite.repository_id,
        "gh.check_suite.id" => instance.check_suite.id,
      }
    end
  )

  def self.call(check_suite:, annotations:)
    new(
      check_suite: check_suite,
      annotations: annotations,
    ).call
  end

  def initialize(check_suite:, annotations:)
    @check_suite = check_suite
    @annotations = annotations
  end

  def call
    return if annotations.blank?

    annotations_truncated = Checks::CreateCheckAnnotations.truncate_if_exceeds_max_annotations(
      annotations, check_suite.repository_id, self.class.name)

    annotation_data = Checks::CreateCheckAnnotations.remove_invalid_annotations(
      annotations_truncated,
      check_suite.repository_id,
      STATS_PREFIX,
      self.class.name,
      "call"
    )

    check_suite.annotations.build(annotation_data)
    GitHub.dogstats.count("#{STATS_PREFIX}.check_annotations_count", annotation_data.count)

    check_suite.save!
  end

  def self.remove_invalid_annotations(annotations, repo_id, stats_prefix, class_name, function)
    invalid_annotations = annotations.select do |annotation|
      # If we are sent an annotation with blank non-integer start and end lines (""), overwrite them with 0
      annotation[:start_line] = 0 if annotation[:start_line].blank?
      annotation[:end_line] = 0 if annotation[:end_line].blank?

      !CheckAnnotation.new(annotation).valid?
    end

    unless invalid_annotations.empty?
      error_messages = []
      invalid_annotations.each do |annotation|
        ca = CheckAnnotation.new(annotation)
        ca.save
        error_messages << { errors: ca.errors.messages }
      end
      GitHub.dogstats.count("#{stats_prefix}.invalid_annotations_count", invalid_annotations.count)
      GitHub.logger.info("encountered invalid annotations", {
        "code.namespace" => class_name,
        "code.function" => "call",
        "gh.repository.id" => repo_id,
        "invalid_check_annotations.count" => invalid_annotations.count,
        "annotation_errors" => error_messages
      })

      annotations -= invalid_annotations
    end
    annotations
  end

  def self.truncate_if_exceeds_max_annotations(annotations, repo_id, class_name)
    if annotations.size > CheckAnnotation::MAX_PER_REQUEST
      GitHub.logger.info("truncating annotations list", {
        "code.namespace" => class_name,
        "code.function" => "call",
        "gh.repository.id" => repo_id,
      })
      return annotations.take(CheckAnnotation::MAX_PER_REQUEST)
    end
    annotations
  end
end
