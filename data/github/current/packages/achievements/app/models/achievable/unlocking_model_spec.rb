# typed: true
# frozen_string_literal: true

class Achievable
  # Public: Describe the unlocking_model types we expect to be associated with an Achievement that is tied to a
  # specific Achievable subclass. This is an abstract superclass; each subclass, defined within this file, passes an
  # instance of a spec subclass to the spec: keyword of its unlocking_event call.
  class UnlockingModelSpec
    # Public: Return an Array<String> of the names of the classes that may be associated with associated Achievements.
    def accepted_types
      []
    end

    # Public: Should associated Achievements have their :unlocking_oid set to non-nil values?
    def expects_oid?
      false
    end

    # Public: Do associated Achievements have an unlocking model specified by a database relation, or is it determined
    # dynamically at render time?
    def dynamic?
      false
    end

    # Public: Retrieve the unlocking models associated with a batch of Dynamic achievements.
    def fetch_dynamic_unlocking_models(*args)
      {}
    end

    # Public: Permit a single unlocking model type. Use this spec subclass to match a single model type.
    class Exact < ::Achievable::UnlockingModelSpec
      def initialize(*klass_names)
        @klass_names = klass_names
      end

      def accepted_types
        @klass_names
      end
    end

    # Public: Disallow unlocking models in the database. Derive them at access time, using a block configured within
    # this spec.
    class Dynamic < Exact
      def initialize(klass_name, &model_block)
        super(klass_name)
        @model_block = model_block
      end

      def dynamic?
        true
      end

      def fetch_dynamic_unlocking_models(*args)
        @model_block.call(*args)
      end
    end

    # Public: Permit both Issues and PullRequests.
    class Issueish < ::Achievable::UnlockingModelSpec
      def accepted_types
        %w(Issue PullRequest)
      end
    end

    # Public: Permit any unlocking model type that may be the subject of a reaction.
    class Reactable < ::Achievable::UnlockingModelSpec
      def accepted_types
        %w(
          CommitComment
          Discussion
          DiscussionComment
          DiscussionPost
          DiscussionPostReply
          Issue
          IssueComment
          PullRequest
          PullRequestReview
          PullRequestReviewComment
          Release
          RepositoryAdvisory
          RepositoryAdvisoryComment
        )
      end
    end

    # Public: Permit a commit as an unlocking event. This accepts an unlocking model of a Repository and expects
    # an accompanying :unlocking_oid in the Achievement.
    class Commit < ::Achievable::UnlockingModelSpec
      def accepted_types
        %w(Repository)
      end

      def expects_oid?
        true
      end
    end
  end
end
