# frozen_string_literal: true

module GitHub
  module Twirp
    class DependabotPullRequests
      class DependencyFileProtobufAdapter < Delegator
        PROTO_CLASS = MonolithTwirp::Dependabot::PullRequests::V1::DependencyFile
        ENCODING_NAMESPACE = PROTO_CLASS::ContentEncoding
        TYPE_NAMESPACE = PROTO_CLASS::Type

        FILE_TYPE = "file"
        SUBMODULE_TYPE = "submodule"
        SYMLINK_TYPE = "symlink"

        def initialize(dependency_file)
          raise ArgumentError unless dependency_file.is_a? Dependabot::DependencyFile

          @dependency_file = dependency_file
        end

        def to_proto
          PROTO_CLASS.new(
            content: content,
            content_encoding: content_encoding,
            deleted: deleted,
            directory: directory,
            mode: mode,
            name: name,
            support_file: support_file,
            symlink_target: symlink_target,
            type: type,
          )
        end

        def content_encoding
          case __getobj__.content_encoding
          when Dependabot::DependencyFile::ContentEncoding::BASE64
            ENCODING_NAMESPACE::CONTENT_ENCODING_BASE64
          when Dependabot::DependencyFile::ContentEncoding::UTF_8
            ENCODING_NAMESPACE::CONTENT_ENCODING_UTF8
          else
            ENCODING_NAMESPACE::CONTENT_ENCODING_INVALID
          end
        end

        def type
          case __getobj__.type
          when FILE_TYPE
            TYPE_NAMESPACE::TYPE_FILE
          when SUBMODULE_TYPE
            TYPE_NAMESPACE::TYPE_SUBMODULE
          when SYMLINK_TYPE
            TYPE_NAMESPACE::TYPE_SYMLINK
          else
            TYPE_NAMESPACE::TYPE_INVALID
          end
        end

        def __getobj__
          @dependency_file
        end
      end
    end
  end
end
