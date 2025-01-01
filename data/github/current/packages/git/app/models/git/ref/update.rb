# typed: true
# frozen_string_literal: true

module Git
  class Ref
    class Update
      include Scientist
      extend T::Sig

      attr_reader :repository, :before_oid, :after_oid, :wiki

      sig { returns(String).checked(:always).on_failure(:raise) }
      attr_reader :refname

      attr_accessor :fast_forward

      alias :wiki? :wiki

      # Public: Representation of a single ref update
      #
      # repository   - Repository the ref update is related to
      # refname      - String fully qualified ref name
      # before_oid   - String OID of the current state of the ref
      # after_oid    - String OID of the attempted state to write
      # fast_forward - Boolean to indicate whether the ref update is a fast-forward update,
      #                or `nil` to indicate fast-forwardness was not checked yet.
      # wiki         - Boolean to indicate if the repository is an unsullied wiki, default is false
      def initialize(repository:, refname:, before_oid:, after_oid:, fast_forward: nil, wiki: false)
        @repository = repository
        @refname = refname
        @before_oid = before_oid
        @after_oid = after_oid
        @fast_forward = fast_forward
        @wiki = wiki

        validate_attributes
      end

      def before_commit
        load_commits
        @before_commit
      end

      def after_commit
        load_commits
        @after_commit
      end

      alias_method :eql?, :==

      def ==(object)
        object.class == self.class && object.state == state
      end

      def hash
        state.hash
      end

      def to_a
        [refname, before_oid, after_oid]
      end

      def paths
        @paths ||= diff.deltas.flat_map(&:paths).uniq
      end

      def diff
        @diff ||= GitHub::Diff.new(repository, before_oid, after_oid)
      end

      sig { returns(T::Boolean) }
      def branch?
        refname.start_with?("refs/heads/")
      end

      sig { returns(T::Boolean) }
      def tag?
        refname.start_with?("refs/tags/")
      end

      sig { returns(T::Boolean) }
      def deletion?
        after_oid == GitHub::NULL_OID
      end

      sig { returns(T::Boolean) }
      def creation?
        before_oid == GitHub::NULL_OID
      end

      sig { returns(T::Boolean) }
      def changed?
        before_oid != after_oid
      end

      # Public: Get the type of that ref.
      #
      # Returns a String.
      def ref_type
        return "branch" if branch?
        return "tag" if tag?
        "unknown"
      end

      # Public: Get the name of the branch being updated, if any.
      #
      # Returns a String or nil. Will return nil if the ref is not for a branch.
      sig { returns(T.nilable(String)) }
      def branch_name
        return unless branch?

        science "refupdate_branch_name_replacement" do |e|
          e.use do
            ref = repository.heads[refname]
            ref&.name
          end

          e.try { unqualified_refname }

          e.compare do |control, candidate|
            # The original implementation will return nil if the branch does not exist on the server. However,
            # this is not expected by any of the usages, therefore, the comparison will ignore the result in this scenario.
            control.nil? || control.b == candidate.b
          end
        end
      end

      # Public: Get the unqlaified name of the ref.
      #
      # Returns a String.
      def unqualified_refname
        # gsub does not support non UTF-8 characters so we must explicitly delete the prefixes based on the ref type

        return refname.delete_prefix("refs/heads/") if branch?
        return refname.delete_prefix("refs/tags/") if tag?

        # We assume that non branch and tag refs use the following format: refs/<namespace>/...
        name = refname.delete_prefix("refs/")
        first_slash = name.index("/")

        return name if first_slash.nil?

        name[first_slash + 1...]
      end

      protected

      def validate_attributes
        unless refname.is_a?(String)
          raise TypeError, "expected refname to be a String, but was #{refname.class}"
        end

        GitRPC::Util.ensure_valid_full_sha1(before_oid)
        GitRPC::Util.ensure_valid_full_sha1(after_oid) unless after_oid == GitHub::PENDING_OID
      end

      def load_commits
        return if @commits_loaded || refname == GitHub::UNKNOWN_REF_NAME || after_oid == GitHub::PENDING_OID

        translated_before_oid = before_oid
        translated_after_oid = after_oid

        if tag?
          oids = [before_oid, after_oid].reject { |oid| oid == GitHub::NULL_OID }
          if oids.any?
            # check if before or after OIDs are referencing a tag object, and translate them to their targetted commits
            tag_objects = repository.rpc.read_objects(oids, :tag, skip_bad: true).index_by { |tag| tag["oid"] }

            translated_before_oid = tag_objects[before_oid]["target"] if tag_objects.key?(before_oid)
            translated_after_oid = tag_objects[after_oid]["target"] if tag_objects.key?(after_oid)
          end
        end

        commit_oids = [translated_before_oid, translated_after_oid].reject { |oid| oid == GitHub::NULL_OID }
        commits = repository.commits.find(commit_oids)

        if (index = commit_oids.index(translated_before_oid)).present?
          @before_commit = commits[index]
        end

        if (index = commit_oids.index(translated_after_oid)).present?
          @after_commit = commits[index]
        end

        @commits_loaded = true
      end

      def state
        [repository, refname, before_oid, after_oid]
      end
    end
  end
end
