# typed: true
# frozen_string_literal: true

class CodeScanning::ToolStatus::FilesExtractedComponent < ApplicationComponent
  attr_reader :label, :system_arguments

  sig { returns(::Turboscan::Proto::ToolStatusExtracted) }
  attr_reader :files

  sig do
    params(
      label: String,
      files: ::Turboscan::Proto::ToolStatusExtracted,
      system_arguments: T.any(String, Integer, Symbol, T::Boolean, T::Array[T.any(String, Integer, Symbol, T::Boolean)])
    ).void
  end
  def initialize(label:, files:, **system_arguments)
    @label = label
    @files = files
    @system_arguments = system_arguments
  end

  def humanize(num:)
    number_to_human(
      num,
      format: "%n%u",
      units: { thousand: "k", million: "M", billion: "G", trillion: "T" }
    )
  end

  def percentage
    return 0 if files.total.zero?

    percentage = (files.extracted.to_f / files.total * 100).round
    # never show zero if any files were scanned, it's confusing to the user
    return 1 if percentage.zero? && files.extracted.nonzero?
    percentage
  end

  def progress_bar_system_arguments
    percentage == 100 ? {} : { bg: :accent_emphasis }
  end
end
