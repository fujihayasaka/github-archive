# typed: strict
# frozen_string_literal: true

module Repositories
  class Push
    include Pushes::CommitsHelper
    include Pushes::ChangedFilesHelper
    include GitHub::Relay::GlobalIdentification
    include GitHub::BatchMethod
    include GH::Domain::Cache::Cachable

    extend GH::RecordTransformer
    extend T::Generic

    ValueType = type_template { { fixed: Repositories::Push } }

    delegate :id, :repository_id, :pusher_id, :before, :after, :ref, :created_at, :updated_at, :pushed_at, :push_type, to: :@attributes

    sig { params(commits: T::Array[::Commit]).returns(T::Array[::Commit]) }
    attr_writer :commits

    sig { override.returns(T::Boolean) }
    attr_reader :spokes_api_fail_fast_enabled

    sig { params(spokes_api_fail_fast_enabled: T::Boolean).returns(T::Boolean) }
    attr_writer :spokes_api_fail_fast_enabled

    sig do
      params(
        id: Integer,
        repository_id: T.nilable(::Integer),
        pusher_id: T.nilable(::Integer),
        before: T.nilable(::String),
        after: T.nilable(::String),
        ref: T.nilable(::String),
        created_at: ActiveSupport::TimeWithZone,
        updated_at: T.nilable(ActiveSupport::TimeWithZone),
        pushed_at: ActiveSupport::TimeWithZone,
        push_type: String,
      ).void
    end
    def initialize(id, repository_id, pusher_id, before, after, ref, created_at, updated_at, pushed_at, push_type)
      @attributes = T.let(PushAttributes.new(id:, repository_id:, pusher_id:, before:, after:, ref:, created_at:, updated_at:, pushed_at:, push_type:), PushAttributes)
      @spokes_api_fail_fast_enabled = T.let(true, T::Boolean)
    end

    sig { params(push: T.nilable(::Push)).returns(T.nilable(Repositories::Push)) }
    def self.from_record(push)
      if push
        new(push.id, push.repository_id, push.pusher_id, push.before, push.after, push.ref, push.created_at, push.updated_at, push.pushed_at, push.push_type)
      else
        nil
      end
    end

    sig { override.params(pushes: T::Array[T.nilable(::Push)]).returns(T::Array[Repositories::Push]) }
    def self.from_records(pushes)
      pushes.map do |push|
        from_record(push)
      end.compact
    end

    sig { returns(String) }
    def platform_type_name
      "Push"
    end

    sig { returns(String) }
    def self.table_name
      "pushes"
    end

    sig { returns(String) }
    def self.polymorphic_name
      "Push"
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      self.class == other.class && self.id == other.id
    end

    batch_method :repository, T.nilable(Repositories::IRepository) do |pushes|
      repos_by_id = Repositories.domain.by_ids(pushes.map(&:repository_id)).index_by(&:id)
      pushes.index_with { |p| repos_by_id[p.repository_id] }
    end
    T.unsafe(self).alias_method :async_repository, :async_batch_repository

    batch_method :pusher, T.nilable(Users::IUser) do |pushes|
      pushers_by_id = Users.domain.by_ids(pushes.map(&:pusher_id)).index_by(&:id)
      pushes.index_with { |p| pushers_by_id[p.pusher_id] }
    end
    T.unsafe(self).alias_method :async_pusher, :async_batch_pusher

    sig { returns(T::Boolean) }
    def initial_commit?
      created? && !deleted?
    end

    sig { params(include_host: T::Boolean).returns(String) }
    def permalink(include_host: true)
      return "" unless repository && before && after
      "#{T.must(repository).permalink(include_host: include_host)}/compare/#{before[0, 10]}...#{after[0, 10]}"
    end
    alias_method :url, :permalink

    sig { returns(T::Boolean) }
    def force_push_push_type?
      push_type == "force_push"
    end

    sig { returns(T.nilable(T::Boolean)) }
    def on_default_branch?
      return unless ref_is_branch?
      branch_name == repository&.default_branch
    end

    sig { params(attr_name: T.untyped).returns(T.untyped) }
    def [](attr_name)
      @attributes.public_send(attr_name) if @attributes.members.include?(attr_name.to_sym) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    end

    sig { override.returns(GH::Domain::Base) }
    def domain
      Repositories.domain.pushes
    end

    sig { override.returns(GH::Domain::Cache::Cachable) }
    def duplicate
      Push.new(id, repository_id, pusher_id, before, after, ref, created_at, updated_at, pushed_at, push_type)
    end
  end
end
