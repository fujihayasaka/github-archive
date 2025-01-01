# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    module Selectors

      TAG_QUALIFIED_REF_PREFIX = T.let("refs/tags/", String)
      HEAD_QUALIFIED_REF_PREFIX = T.let("refs/heads/", String)
      HEAD_POINTER = T.let("HEAD", String)

      TAG = :tag
      HEAD = :head
      OID = :oid
      REVISION = :revision
      QUALIFIED_REF = :qualified_ref

      # Returns the resolve object selectors for the given ref and path.
      sig do
        params(
          repository: Repository,
          ref: T.nilable(String),
          path: T.nilable(String)
        ).returns(T::Array[SelectorObject])
      end
      def self.build(repository:, ref:, path:)
        by_ref_selector = if ref.blank?
          build_selector(ref_type: HEAD, ref_name: repository.default_branch, path: path)
        else
          # When ref is the qualified ref name of a tag/branch
          # we can optimize and add only one selector.
          try_build_by_qualified_ref_name(qualified_ref_name: ref, path:)
        end

        return [by_ref_selector] if by_ref_selector.present?

        ref_name = T.must(ref)

        if ref == repository.default_branch
          return [build_selector(ref_type: HEAD, ref_name:, path:)]
        end

        selectors = T.let([], T::Array[SelectorObject])

        selectors << build_selector(ref_type: HEAD, ref_name:, path:)
        selectors << build_selector(ref_type: TAG, ref_name:, path:)

        if ref_name.start_with?("refs/")
          selectors << build_selector(ref_type: QUALIFIED_REF, ref_name:, path:)
        else
          selectors << build_selector(ref_type: OID, ref_name:, path:)
        end

        selectors << build_selector(ref_type: REVISION, ref_name:, path:)

        selectors
      end

      # Returns a new instance by trying guess the ref type from the qualified ref name.
      sig { params(qualified_ref_name: String, path: T.nilable(String)).returns(T.nilable(SelectorObject)) }
      def self.try_build_by_qualified_ref_name(qualified_ref_name:, path:)
        # When ref is the full name of a tag/branch
        # we can optimize and add only one selector.
        if HEAD_POINTER == qualified_ref_name
          return ByRef.new(
            ref_type: HEAD,
            ref_name: qualified_ref_name,
            qualified_ref_name:,
            path:
          )
        end
        if Regexp.new("^#{HEAD_QUALIFIED_REF_PREFIX}[^/]+$").match?(qualified_ref_name)
          return build_selector(ref_type: HEAD, ref_name: qualified_ref_name, path: path)
        end
        if Regexp.new("^#{TAG_QUALIFIED_REF_PREFIX}[^/]+$").match?(qualified_ref_name)
          return build_selector(ref_type: TAG, ref_name: qualified_ref_name, path: path)
        end

        nil
      end
      private_class_method :try_build_by_qualified_ref_name

      # Returns a new instance by the given ref type, ref name and path.
      sig { params(ref_type: Symbol, ref_name: String, path: T.nilable(String)).returns(SelectorObject) }
      def self.build_selector(ref_type:, ref_name:, path:)
        case ref_type
        when TAG
          ByRef.new(
            ref_type: TAG,
            ref_name: ref_name(qualified_ref_name: ref_name, prefix: TAG_QUALIFIED_REF_PREFIX),
            qualified_ref_name: qualified_ref_name(TAG_QUALIFIED_REF_PREFIX, ref_name),
            path:
          )
        when HEAD
          ByRef.new(
            ref_type: HEAD,
            ref_name: ref_name(qualified_ref_name: ref_name, prefix: HEAD_QUALIFIED_REF_PREFIX),
            qualified_ref_name: qualified_ref_name(HEAD_QUALIFIED_REF_PREFIX, ref_name),
            path:
          )
        when QUALIFIED_REF
          ByRef.new(
            ref_type: QUALIFIED_REF,
            ref_name:,
            qualified_ref_name: ref_name,
            path:
          )
        when OID
          ByObjectId.new(
            ref_type: OID,
            ref_name:,
            qualified_ref_name: ref_name,
            path:
          )
        when REVISION
          ByRevision.new(
            ref_type: REVISION,
            ref_name:,
            qualified_ref_name: ref_name,
            path:
          )
        else
          raise "unexpected ref type: #{ref_type}"
        end
      end
      private_class_method :build_selector

      # Returns the ref name from the treeish by removing the prefix.
      sig { params(qualified_ref_name: String, prefix: String).returns(String) }
      def self.ref_name(qualified_ref_name:, prefix:)
        return qualified_ref_name unless qualified_ref_name.start_with?(prefix)

        qualified_ref_name.sub(prefix, "")
      end
      private_class_method :ref_name

      # return the treeish for the given prefix and ref name.
      sig { params(prefix: String, ref_name: String).returns(String) }
      def self.qualified_ref_name(prefix, ref_name)
        return ref_name if ref_name.start_with?(prefix)

        # Copying logic from
        # https://github.com/github/github/blob/581f97ea52e4dd700ebd37813eeaf91c775e3823/packages/spokes_api/app/public/spokesapi/client.rb#L947-L954
        qualified_ref = "#{prefix}#{ref_name}"
        qualified_ref = qualified_ref.gsub(%r{/{2,}}, "/") if qualified_ref.include?("//")
        qualified_ref
      end
      private_class_method :qualified_ref_name

    end
  end
end
