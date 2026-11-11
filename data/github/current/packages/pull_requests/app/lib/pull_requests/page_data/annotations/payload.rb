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
      include Comparable

      sig { params(other: BasicObject).returns(T.nilable(Integer)) }
      def <=>(other)
        case other
        when self.class
          sort_order <=> other.sort_order
        else
          nil
        end
      end

      sig { returns(Integer) }
      protected def sort_order
        case self
        when Notice then 0
        when Warning then 1
        when Failure then 2
        else T.absurd(self)
        end
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
  end
end
