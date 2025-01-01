# typed: true
# frozen_string_literal: true

module GitHub
  # Loads labels for a given context by IDs.
  class LabelLoader
    # Initializes a LabelLoader with a context.
    #
    # context - Any object that maintains a collection of Labels to load from.
    def initialize(context)
      @context = context
    end

    # Public: Loads the labels by ID.
    #
    # labels - Array of String or Integer Label IDs.
    #
    # Returns an Array of Label objects.
    def fetch(label_ids)
      ids = normalize(label_ids)
      return [] if ids.empty?

      @context.find_labels(ids)
    end

    # Normalizes the input label IDs.
    #
    # labels - Array of String or Integer Label IDs.
    #
    # Returns a normalized Array of Integer Label IDs.
    def normalize(label_ids)
      return [] if label_ids.nil? || label_ids.empty?

      ids = []
      label_ids.each do |label_id|
        ids << label_id.to_i unless label_id.blank?
      end
      ids
    end
  end
end
