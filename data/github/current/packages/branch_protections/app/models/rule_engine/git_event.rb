# typed: strict
# frozen_string_literal: true

module RuleEngine
  class GitEvent < RepositoryEvent
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { returns(RuleEngine::MetadataSources::Base) }
    attr_reader :metadata_source

    sig { returns(Types::Phase) }
    attr_reader :phase

    sig { returns(T::Array[Git::Ref::Update]) }
    attr_reader :skipped_ref_updates

    sig { returns(T::Boolean) }
    attr_reader :is_writing
    alias :is_writing? :is_writing

    sig do
      params(
        repository: Repository,
        ref_updates: T::Array[Git::Ref::Update],
        actor: Types::Actor,
        metadata_source: RuleEngine::MetadataSources::Base,
        phase: Types::Phase,
        commit_refs: T::Boolean, # does this git operation come from the CLI?
        is_writing: T::Boolean, # is this event attempting to write to git
      ).void
    end
    def initialize(repository, ref_updates, actor, metadata_source:, phase:, commit_refs: false, is_writing: true)
      super(repository, actor)
      raise ArgumentError if ref_updates.size == 0

      skipped_ref_updates, ref_updates = ref_updates.partition { |ref_update| is_internal_ref?(ref_update) }
      @ref_updates = ref_updates
      @skipped_ref_updates = T.let(skipped_ref_updates, T::Array[Git::Ref::Update])

      @metadata_source = metadata_source
      @phase = phase
      @commit_refs = commit_refs
      @is_writing = is_writing
    end

    sig { override.returns(T::Array[Git::Ref::Update]) }
    def event_actions
      @ref_updates
    end

    sig { returns(T::Boolean) }
    def commit_refs?
      @commit_refs
    end

    sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
    def additional_context; end

    sig { returns(String) }
    def metadata_source_name
      metadata_source.name
    end

    sig do
      params(ref_update: Git::Ref::Update, cursor: T.nilable(String))
        .returns(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::BlobCandidate])
    end
    def blobs(ref_update, cursor)
      metadata_source.blobs(repository, phase, ref_update, cursor)
    end

    sig do
      params(ref_update: Git::Ref::Update, cursor: T.nilable(String))
        .returns(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::CommitCandidate])
    end
    def commits(ref_update, cursor)
      metadata_source.commits(repository, phase, ref_update, cursor)
    end

    sig { returns(RuleEvaluationContext) }
    def legacy_evaluation_context
      RuleEvaluationContext.new(repository, actor, metadata_source:, phase:, additional_context: additional_context)
    end

    sig { override.params(exception: StandardError).returns(T::Array[RuleSuite]) }
    def handle_exception(exception)
      raise exception unless exception.is_a?(GitRPC::ObjectMissing)

      rule_suites = (event_actions + skipped_ref_updates).map do |ref_update|
        RuleSuite.object_missing(repository, actor, ref_update: ref_update)
      end

      ProtectedBranchLegacyInstrumenter.instrument_decision(rule_suites, repository)

      rule_suites
    end

    sig { override.params(rule_suites: T::Array[RuleSuite]).void }
    def record_results(rule_suites)
      ProtectedBranchLegacyInstrumenter.instrument_decision(rule_suites, repository)
      rule_suites.each(&:log_evaluation)

      # We may not have a write connection if we get here via SynchronizePullRequestJob, so get one.
      ActiveRecord::Base.connected_to(role: :writing) do
        rule_suites.filter(&:should_persist?).each do |rule_suite|
          rule_suite.save!
        end
      end
    end

    protected

    sig { params(ref_update: Git::Ref::Update).returns(T::Hash[Symbol, T.untyped]) }
    def pull_request_metadata(ref_update)
      if pull_request = ref_update.try(:pull_request)
        {
          pull_request: {
            id: pull_request.id,
            head_sha: pull_request.head_sha,
            policy_sha: pull_request.merge_commit_sha,
            merge_base_sha: pull_request.find_best_merge_base_sha(base_sha: ref_update.before_oid),
          }
        }
      else
        {}
      end
    end

    sig { params(ref_update: Git::Ref::Update).returns(T::Boolean) }
    private def is_internal_ref?(ref_update)
      return false if ref_update.refname == GitHub::UNKNOWN_REF_NAME

      case ref_update.refname.b
      when %r{\Arefs/pull(/|\z)},
        %r{\Arefs/__gh__(/|\z)},
        %r{\A#{MergeQueue::READ_ONLY_REF_PREFIX.delete_suffix('/')}(/|\z)}
        return true
      end

      false
    end
  end
end
