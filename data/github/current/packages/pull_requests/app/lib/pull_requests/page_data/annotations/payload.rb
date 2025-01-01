# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Annotations
  class Payload
    class AnnotationLevel < T::Enum
      enums do
        Notice = new("NOTICE")
        Warning = new("WARNING")
        Failure = new("FAILURE")
      end
    end

    class AnnotationLevel
      sig { params(other: AnnotationLevel).returns(T::Boolean) }
      def >(other)
        return true if self == AnnotationLevel::Failure
        return true if self == AnnotationLevel::Warning && other == AnnotationLevel::Notice
        false
      end
      sig { params(other: AnnotationLevel).returns(T::Boolean) }
      def <(other)
        return true if self == AnnotationLevel::Notice
        return true if self == AnnotationLevel::Warning && other == AnnotationLevel::Failure
        false
      end
      sig { params(other: AnnotationLevel).returns(T::Boolean) }
      def ==(other)
        self.serialize == other.serialize
      end
    end

    class CheckRun < T::Struct
      const :detailsUrl, String
      const :name, String
    end

    class Annotation < T::Struct
      const :annotationLevel, AnnotationLevel
      const :appAvatarAltText, String
      const :appAvatarUrl, String
      const :checkRun, CheckRun
      const :checkSuiteName, T.nilable(String)
      const :databaseId, Integer
      const :endLine, Integer
      const :id, String
      const :message, String
      const :path, String
      const :pathDigest, String
      const :startLine, Integer
      const :title, String
    end

    sig do
      params(
        annotations: T::Array[Loader::Annotation],
      ).returns(T::Array[Annotation])
    end
    def self.call(annotations)
      new.call(annotations)
    end

    sig do
      params(
        annotations: T::Array[Loader::AnnotationLevelWithPath],
      ).returns(T::Hash[String, AnnotationLevel])
    end
    def self.annotations_highest_level(annotations)
      new.annotations_highest_level(annotations)
    end

    sig { params(annotations: T::Array[Loader::Annotation]).returns(T::Array[Annotation]) }
    def call(annotations)
      annotations.map do |annotation|
        Annotation.new(
          id: annotation.id,
          annotationLevel: AnnotationLevel.deserialize(annotation.annotation_level.to_s.upcase),
          appAvatarAltText: annotation.app_avatar_alt_text,
          appAvatarUrl: annotation.app_avatar_url,
          checkRun: CheckRun.new(
            detailsUrl: annotation.check_run.details_url,
            name: annotation.check_run.name,
          ),
          checkSuiteName: annotation.check_suite_name,
          databaseId: annotation.database_id,
          endLine: annotation.end_line,
          message: annotation.message,
          path: annotation.path,
          pathDigest: annotation.path_digest,
          startLine: annotation.start_line,
          title: annotation.title
        )
      end
    end

    sig { params(annotations: T::Array[Loader::AnnotationLevelWithPath]).returns(T::Hash[String, AnnotationLevel]) }
    def annotations_highest_level(annotations)
      annotations.each_with_object({}) do |annotation, highest_level|
        current_level = AnnotationLevel.deserialize(annotation.annotation_level.to_s.upcase)
        if highest_level[annotation.path].nil? || current_level > highest_level[annotation.path]
          highest_level[annotation.path] = current_level
        end
      end.transform_values(&:serialize)
    end

    sig { params(annotations: T::Array[Annotation]).returns(T::Hash[String, AnnotationLevel]) }
    def payload_annotations_highest_level(annotations)
      annotations.each_with_object({}) do |annotation, highest_level|
        current_level = annotation.annotationLevel
        if highest_level[annotation.path].nil? || current_level > highest_level[annotation.path]
          highest_level[annotation.path] = current_level
        end
      end
    end
  end
end
