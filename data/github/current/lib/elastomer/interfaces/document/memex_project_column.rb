# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document

      class Assignee < T::Struct
        extend T::Sig

        prop :id, T.nilable(Integer)
        prop :display_login, String

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            id: id,
            login: display_login,
          }
        end
      end

      class Iteration < T::Struct
        extend T::Sig

        prop :id, T.nilable(String)
        prop :title, T.nilable(String)
        prop :duration, T.nilable(Integer)
        prop :start_date, T.nilable(String)

        sig { returns(T::Hash[Symbol, T.any(String, Integer)]) }
        def to_hash
          {
            id: id,
            title: title,
            duration: duration,
            start_date: start_date,
          }
        end
      end

      class Label < T::Struct
        extend T::Sig

        prop :id, T.nilable(Integer)
        prop :name, T.nilable(String)
        prop :repository_id, T.nilable(Integer)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            id: id,
            name: name,
            repository_id: repository_id,
          }
        end
      end

      class LinkedPullRequests < T::Struct
        extend T::Sig

        prop :number, T.nilable(String)
        prop :id, T.nilable(Integer)
        prop :repository_id, T.nilable(Integer)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            id: id,
            number: number,
            repository_id: repository_id,
          }
        end
      end

      class Milestone < T::Struct
        extend T::Sig

        prop :id, T.nilable(Integer)
        prop :repository_id, T.nilable(Integer)
        prop :title, T.nilable(String)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            id: id,
            title: title,
            repository_id: repository_id,
          }
        end
      end

      class Repository < T::Struct
        extend T::Sig

        prop :id, T.nilable(Integer)
        prop :owner_id, T.nilable(Integer)
        prop :owner_type, T.nilable(String)
        prop :full_name, T.nilable(String)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            id: id,
            owner_id: owner_id,
            owner_type: owner_type,
            full_name: full_name,
          }
        end
      end

      class Reviewers < T::Struct
        extend T::Sig

        prop :actor_id, T.nilable(Integer)
        prop :actor_slug, T.nilable(String)
        prop :actor_type, T.nilable(String)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            actor_id: actor_id,
            actor_slug: actor_slug,
            actor_type: actor_type,
          }
        end
      end

      class SingleSelect < T::Struct
        extend T::Sig

        const :id, String
        const :name, T.nilable(String)

        sig { returns(T::Hash[Symbol, String]) }
        def to_hash
          {
            id:,
            name:,
          }
        end
      end

      class Tracks < T::Struct
        extend T::Sig

        prop :completed, T.nilable(Integer)
        prop :total, T.nilable(Integer)
        prop :percent, T.nilable(Integer)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            total: total,
            completed: completed,
            percent: percent,
          }
        end
      end

      class IssueType < T::Struct
        extend T::Sig

        prop :id, T.nilable(Integer)
        prop :name, T.nilable(String)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            id: id,
            name: name,
          }
        end
      end

      class ParentIssue < T::Struct
        extend T::Sig

        prop :id, Integer
        prop :nwo_reference, String
        prop :title, String

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            id: id,
            nwo_reference: nwo_reference,
            title: title,
          }
        end
      end

      class SubIssuesProgress < T::Struct
        extend T::Sig

        prop :total, T.nilable(Integer)
        prop :percent_completed, T.nilable(Integer)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            total: total,
            percent_completed: percent_completed,
          }
        end
      end
    end
  end

end
