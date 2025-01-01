# typed: true
# frozen_string_literal: true

module RuleEngine
  # Context required by the rule engine about a specific git rule evaluation request
  class RuleEvaluationContext
    extend T::Sig

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(Regex::RE2Helper) }
    attr_reader :regex_helper

    sig { returns(T.nilable(Types::Actor)) }
    attr_reader :actor

    sig { returns(T.nilable(Types::Phase)) }
    attr_reader :phase

    sig do
      params(
        repository: Repository,
        actor: T.nilable(Types::Actor),
        metadata_source: T.nilable(RuleEngine::MetadataSources::Base),
        phase: T.nilable(Types::Phase),
        additional_context: T::Hash[Symbol, T.untyped]
      ).void
    end
    def initialize(repository, actor = nil, metadata_source: nil, phase: nil, additional_context: {})
      @repository = repository
      @additional_context = additional_context
      @actor = actor
      @metadata_source = metadata_source || RuleEngine::MetadataSources::Spokes.new
      @phase = phase
      @compiled_regexes = {}
      @regex_helper = Regex::RE2Helper.new
    end

    def metadata_source_name
      @metadata_source.name
    end

    sig { returns(T::Boolean) }
    def merge_box_evaluation?
      @additional_context[:merge_box_evaluation] || false
    end

    sig { returns(T::Boolean) }
    def commit_refs_evaluation?
      @additional_context[:commit_refs_evaluation] || false
    end

    sig { returns(T::Boolean) }
    def blob_evaluation?
      @additional_context[:blob_evaluation] || false
    end

    sig { params(value: String, regex: String).returns(T::Boolean) }
    def matches_regex?(value, regex)
      @regex_helper.matches?(value, regex)
    end

    sig do
      params(ref_update: Git::Ref::Update, cursor: T.nilable(String))
        .returns(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::BlobCandidate])
    end
    def blobs(ref_update, cursor)
      @metadata_source.blobs(@repository, @phase, ref_update, cursor)
    end

    sig do
      params(ref_update: Git::Ref::Update, cursor: T.nilable(String))
        .returns(RuleEngine::MetadataSources::Collection[RuleEngine::MetadataSources::Types::CommitCandidate])
    end
    def commits(ref_update, cursor)
      @metadata_source.commits(@repository, @phase, ref_update, cursor)
    end

    sig { params(ref_update: Git::Ref::Update).returns(T.nilable(MergeQueue)) }
    def merge_queue_for(ref_update)
      return unless repo_merge_queue_enabled?
      return unless ref_update.branch? && (branch_name = ref_update.branch_name)

      ensure_merge_queue_cache
      repository.merge_queue_for(branch: branch_name)
    end

    def merge_queue_head_oids
      return {} unless repo_merge_queue_enabled?
      return @merge_queue_head_oids if defined?(@merge_queue_head_oids)

      ensure_merge_queue_cache
      queues = repository.merge_queues.compact
      @merge_queue_head_oids = MergeQueue.head_oids_for(queues: queues, repository: repository)
    end

    def server_merge?
      @additional_context[:server_merge] == true
    end

    def fetch_and_merge?
      @additional_context[:fetch_and_merge] == true
    end

    def ref_in_merge_queue?(ref_update)
      return false unless ref_update.branch?
      return false unless repo_merge_queue_enabled?

      ensure_merge_queue_cache
      queue = repository.merge_queue_for(branch: ref_update.branch_name)

      return false unless queue

      queue.all_merge_commit_shas.include?(ref_update.after_oid)
    end

    def spokes_push_state
      GitHub.context[:spokesapi_push_state]
    end

    def repo_merge_queue_enabled?
      return @is_repo_merge_queue_enabled if defined?(@is_repo_merge_queue_enabled)
      @is_repo_merge_queue_enabled = repository.merge_queue_enabled?
    end

    private

    def compile_regex(regex)
      @regex_helper.compile(regex)
    end

    def ensure_merge_queue_cache
      return if !repository.supports_protected_branches? || BranchProtectionsConfig.new(repository).branch_protection_disabled?
      return if @merge_queue_cache
      GitHub::PrefillAssociations.prefill_associations(repository, :merge_queues)
      @merge_queue_cache = true
    end
  end
end
