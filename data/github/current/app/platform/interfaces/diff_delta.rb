# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module DiffDelta
      include Platform::Interfaces::Base

      description "representation of a diff delta"

      field :path, String, "The path of this changed file", null: false, visibility: :internal

      def path
        diff_sha_and_path[1].dup.force_encoding("UTF-8").scrub!
      end

      field :path_digest, String, "The hashed path of the changed file", null: false, visibility: :internal

      def path_digest
        Digest::SHA256.hexdigest(path)
      end

      field :change_type, Enums::PatchStatus, description: "How the file was changed", null: false

      def change_type
        case @object.status
        when "D" then :deleted
        when "A" then :added
        when "M" then :modified
        when "R" then :renamed
        else :unknown
        end
      end

      def diff_sha_and_path
        if @object.is_a?(GitRPC::Diff::Delta)
          a = @object.old_file
          b = @object.new_file
          @object.deleted? ? [a.oid, a.path] : [b.oid, b.path]
        else
          @object.deleted? ? [@object.a_sha, @object.a_path] : [@object.b_sha, @object.b_path]
        end
      end

      field :additions, Integer, description: "The number of additions to the file.", null: false

      def additions
        @object.additions || 0
      end

      field :deletions, Integer, description: "The number of deletions to the file.", null: false

      def deletions
        @object.deletions || 0
      end
    end
  end
end
