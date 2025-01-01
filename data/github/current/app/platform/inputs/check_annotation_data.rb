# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CheckAnnotationData < Platform::Inputs::Base
      MAXIMUM_PER_REQUEST = 50

      description "Information from a check run analysis to specific lines of code."

      argument :path, String, "The path of the file to add an annotation to.", required: true

      argument :location, CheckAnnotationRange, "The location of the annotation", required: true

      argument :annotation_level, Enums::CheckAnnotationLevel, "Represents an annotation's information level", required: true

      argument :message, String, "A short description of the feedback for these lines of code.", required: true

      argument :title, String, "The title that represents the annotation.", required: false

      argument :raw_details, String, "Details about this annotation.", required: false

      def self.hash_from_input(annotation)
        annotation_hash = annotation.to_h
        # need to rename keys for the model
        annotation_hash[:warning_level] = annotation_hash.delete(:annotation_level)
        annotation_hash[:filename] = annotation_hash.delete(:path)
        location_info = annotation_hash.delete(:location)
        location_info.each_pair do |location, value|
          annotation_hash[location] = value
        end

        annotation_hash
      end
    end
  end
end
