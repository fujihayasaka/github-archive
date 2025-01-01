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
        ).returns(T::Array[SelectorGroup])
      end
      def self.build(repository:, ref:, path:)
        base_ref_name = ref.presence
        ref_name = base_ref_name&.delete_prefix("/")

        selectors = T.let([], T::Array[SelectorGroup])

        if ref_name.nil?
          selectors << SelectorGroup.new(ref_name: repository.default_branch, qualified_ref_name: qualified_ref_name(repository.default_branch, HEAD_QUALIFIED_REF_PREFIX), path:)
        elsif ref_name.starts_with?("refs/")
          selectors << SelectorGroup.new(ref_name: base_ref_name, qualified_ref_name: ref_name, path:)
        else
          selectors << SelectorGroup.new(ref_name: base_ref_name, qualified_ref_name: qualified_ref_name(ref_name, HEAD_QUALIFIED_REF_PREFIX), path:)
          selectors << SelectorGroup.new(ref_name: base_ref_name, qualified_ref_name: qualified_ref_name(ref_name, TAG_QUALIFIED_REF_PREFIX), path:)

          selectors << SelectorGroup.new(ref_name: base_ref_name, qualified_ref_name: ref_name, path:)
        end

        selectors
      end

      # Return the treeish for the given prefix and ref name.
      sig { params(ref_name: String, prefix: String).returns(String) }
      def self.qualified_ref_name(ref_name, prefix)
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
