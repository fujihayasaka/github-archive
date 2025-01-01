# typed: strict
# frozen_string_literal: true

module RuleEngine
  class EventActionRefUpdate < ApplicationRecord::Domain::Repositories
    extend T::Helpers

    belongs_to :repository
    has_one :rule_suite, class_name: "RuleEngine::RuleSuite", dependent: :destroy, foreign_key: "event_action_id", inverse_of: :event_action

    validates :repository_id, presence: true
    validates :ref_name, presence: true
    validates :before_oid, presence: true
    validates :after_oid, presence: true

    sig { params(event_action: T.nilable(EventActionRefUpdate), ref_update: Git::Ref::Update).returns(RuleEngine::EventActionRefUpdate) }
    def self.from_ref_update(event_action, ref_update)
      if event_action
        event_action.repository_id = ref_update.repository.id
        event_action.ref_name = ref_update.refname
        event_action.before_oid = ref_update.before_oid
        event_action.after_oid = ref_update.after_oid
        event_action.policy_oid = ref_update.try(:policy_oid)

        # Save the new values only if the object was previously saved.
        # We sometimes get here on a read-only database connection
        event_action.save! if event_action.persisted? && event_action.changed?
        event_action
      else
        new(
          repository_id: ref_update.repository.id,
          ref_name: ref_update.refname,
          before_oid: ref_update.before_oid,
          after_oid: ref_update.after_oid,
          policy_oid: ref_update.try(:policy_oid),
        )
      end
    end

    sig { returns(Git::Ref::Update) }
    def ref_update
      if policy_oid
        Git::Branch::Update.new(repository:, refname: ref_name, before_oid:, after_oid:, policy_oid:)
      else
        Git::Ref::Update.new(repository:, refname: ref_name, before_oid:, after_oid:)
      end
    end

    batch_method(:after_commit, T.nilable(Commit)) do |event_actions|
      event_actions = T.cast(event_actions, T::Enumerable[EventActionRefUpdate])

      event_actions_by_repo = event_actions.group_by(&:repository)
      last_commits = event_actions_by_repo.filter_map do |repo, repo_actions|
        next unless repo
        oids = repo_actions.map(&:after_oid).compact.filter { |oid| oid != GitHub::PENDING_OID }
        [repo, repo.rpc.read_objects(oids, :commit, true).compact.map { |commit| Commit.new(repo, commit) }.map { |commit| [commit.oid, commit] }.to_h]
      end.to_h

      event_actions.map do |event_action|
        commit = event_action.repository ? last_commits[T.must(event_action.repository)]&.[](event_action.after_oid) : nil
        [event_action, commit]
      end.to_h
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def instrument_data
      {
        repository_id: repository_id,
        ref_name: ref_name,
        before_oid: before_oid,
        after_oid: after_oid,
        policy_oid: policy_oid,
      }
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def json_payload
      {
        repository_id: repository_id,
        ref_name: ref_name,
        before_oid: before_oid != GitHub::NULL_OID ? before_oid : nil,
        after_oid: after_oid != GitHub::NULL_OID ? after_oid : nil,
        policy_oid: policy_oid != GitHub::NULL_OID ? policy_oid : nil,
        commit: commit_json,
      }
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def evaluation_data
      {
        "gh.branch_protection_rule.rule_suite.ref_name": ref_update.refname.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: ""),
        "gh.branch_protection_rule.rule_suite.before_commit": ref_update.before_oid,
        "gh.branch_protection_rule.rule_suite.after_commit": ref_update.after_oid,
        "gh.branch_protection_rule.rule_suite.rule_commit": ref_update.try(:policy_commit_oid),
      }
    end

    private

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def commit_json
      return nil if after_commit.nil?
      commit = T.must(after_commit)
      {
        message: commit.message,
        short_message_html_link: (GitHub::Goomba::TitleMarkdownFilter.call(commit.short_message_html) unless commit.short_message_html.blank?),
      }
    end
  end
end
