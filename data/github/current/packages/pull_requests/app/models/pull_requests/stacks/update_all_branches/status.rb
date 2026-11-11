# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module UpdateAllBranches
      class Status
        TTL = T.let(10.minutes, ActiveSupport::Duration)

        class JobState < T::Enum
          enums do
            Pending = new("PENDING")
            Running = new("RUNNING")
            Done = new("DONE")
          end

          sig { params(args: T.untyped).returns(String) }
          def as_json(*args) = serialize

          sig { params(str: String).returns(JobState) }
          def self.from_json(str) = deserialize(str)
        end

        module PullRequestState
          extend T::Helpers

          JsonRep = T.type_alias { T::Hash[Symbol, String] }

          sealed!
          interface!

          # NOTE: `data` should be a `JsonRep` here, but it is marked as
          #  untyped so we can handle unexpected data shapes.
          sig { params(data: T.untyped).returns(PullRequestState) }
          def self.from_json(data)
            case data
            in { state: "SUCCEEDED", before:, after: }
              Succeeded.new(old_head_oid: before, new_head_oid: after)
            in { state: "FAILED", message: }
              Failed.new(message:)
            in { state: "CONFLICTED" }
              Conflicted.new
            else
              detail = case data
              when Hash then "keys=#{data.keys}"
              else "value=#{data.inspect}"
              end
              raise ArgumentError, "Invalid state data: #{data.class} #{detail}"
            end
          end

          sig { abstract.params(options: T.untyped).returns(JsonRep) }
          def as_json(options = {}); end

          sig { abstract.returns(T::Boolean) }
          def succeeded?; end

          sig { abstract.returns(T::Boolean) }
          def conflicted?; end

          class Failed < T::Struct
            include PullRequestState
            const :message, String

            sig { override.params(options: T.untyped).returns(JsonRep) }
            def as_json(options = {}) = { state: "FAILED", message: }

            sig { override.returns(T::Boolean) }
            def succeeded? = false

            sig { override.returns(T::Boolean) }
            def conflicted? = false

            sig { params(other: BasicObject).returns(T::Boolean) }
            def ==(other)
              case other
              when Failed then other.message == message
              else false
              end
            end
          end

          class Conflicted < T::Struct
            include PullRequestState

            sig { override.params(options: T.untyped).returns(JsonRep) }
            def as_json(options = {}) = { state: "CONFLICTED" }

            sig { override.returns(T::Boolean) }
            def succeeded? = false

            sig { override.returns(T::Boolean) }
            def conflicted? = true

            sig { params(other: BasicObject).returns(T::Boolean) }
            def ==(other)
              case other
              when Conflicted then true
              else false
              end
            end
          end

          class Succeeded < T::Struct
            include PullRequestState
            const :old_head_oid, String
            const :new_head_oid, String

            sig { override.params(options: T.untyped).returns(JsonRep) }
            def as_json(options = {}) = { state: "SUCCEEDED", before: old_head_oid, after: new_head_oid }

            sig { override.returns(T::Boolean) }
            def succeeded? = true

            sig { override.returns(T::Boolean) }
            def conflicted? = false

            sig { params(other: BasicObject).returns(T::Boolean) }
            def ==(other)
              case other
              when Succeeded
                other.old_head_oid == old_head_oid && other.new_head_oid == new_head_oid
              else false
              end
            end
          end

          class Pending
            include PullRequestState

            sig { override.params(options: T.untyped).returns(JsonRep) }
            def as_json(options = {}) = { state: "PENDING" }

            sig { override.returns(T::Boolean) }
            def succeeded? = false

            sig { override.returns(T::Boolean) }
            def conflicted? = false

            sig { params(other: BasicObject).returns(T::Boolean) }
            def ==(other)
              case other
              when Pending then true
              else false
              end
            end
          end
        end

        KEY_PREFIX = "pull_requests/stacks/update_all_branches_result/"

        sig { params(stack: PullRequests::Stack).returns(T.nilable(Status)) }
        def self.find(stack:)
          store = PullRequests::KV.for_repository(T.must(stack.repository))
          json = store.get("#{KEY_PREFIX}#{stack.id}").value { nil }
          return nil if json.nil?

          raw_data = JSON.parse(json, symbolize_names: true)
          pull_request_states = raw_data.fetch(:pull_request_states)
            .transform_keys { _1.to_s.to_i }
            .transform_values { PullRequestState.from_json(_1) }
          job_state = JobState.from_json(raw_data.fetch(:job_state))
          new(
            stack,
            start_pull_request_id: raw_data.fetch(:start_pull_request_id),
            job_state:,
            pull_request_states:,
            persisted: true,
          )
        rescue JSON::ParserError, KeyError, ArgumentError => e
          Failbot.report(e, "gh.pull_request_stack.id" => stack.id.to_s)
          nil
        end

        sig { params(stack: PullRequests::Stack, start_pull_request: PullRequest).returns(Status) }
        def self.build(stack:, start_pull_request:)
          new(
            stack,
            start_pull_request_id: start_pull_request.id,
            job_state: JobState::Pending,
            pull_request_states: {},
            persisted: false,
          )
        end

        sig do
          params(
            stack: PullRequests::Stack,
            start_pull_request_id: Integer,
            job_state: JobState,
            pull_request_states: T::Hash[Integer, PullRequestState],
            persisted: T::Boolean,
          ).void
        end
        def initialize(stack, start_pull_request_id:, job_state: JobState::Pending, pull_request_states: {}, persisted: false)
          @stack = stack
          @start_pull_request_id = start_pull_request_id
          @job_state = job_state
          @pull_request_states = pull_request_states
          @persisted = persisted
        end

        sig { returns(JobState) }
        attr_reader :job_state

        sig { returns(T::Boolean) }
        def done?
          case @job_state
          when JobState::Done then true
          when JobState::Pending, JobState::Running then false
          else T.absurd(@job_state)
          end
        end

        sig { void }
        def save!
          store = PullRequests::KV.for_repository(T.must(@stack.repository))
          store.set("#{KEY_PREFIX}#{@stack.id}", to_json, expires: TTL.from_now)
          @persisted = true
        end

        sig { params(pull_request: PullRequest, message: String).void }
        def mark_failed(pull_request:, message:)
          @pull_request_states[pull_request.id] = PullRequestState::Failed.new(message:)
          @job_state = JobState::Done
          @persisted = false
        end

        sig { params(pull_request: PullRequest).void }
        def mark_conflicted(pull_request:)
          @pull_request_states[pull_request.id] = PullRequestState::Conflicted.new
          @job_state = JobState::Done
          @persisted = false
        end

        sig { params(pull_request: PullRequest, old_head_oid: String, new_head_oid: String).void }
        def mark_successful(pull_request:, old_head_oid:, new_head_oid:)
          @pull_request_states[pull_request.id] = PullRequestState::Succeeded.new(old_head_oid:, new_head_oid:)
          @job_state = JobState::Running
          @persisted = false
        end

        sig { void }
        def mark_done
          return if @job_state == JobState::Done

          @job_state = JobState::Done
          @persisted = false
        end

        sig { params(pull_request: ::PullRequest).returns(PullRequestState) }
        def for_pull_request(pull_request)
          @pull_request_states[pull_request.id] || PullRequestState::Pending.new
        end

        sig { returns(Integer) }
        def start_pull_request_id = @start_pull_request_id

        sig { params(options: T.untyped).returns({ start_pull_request_id: Integer, job_state: String, pull_request_states: T::Hash[String, PullRequestState::JsonRep] }) }
        def as_json(options = {})
          {
            start_pull_request_id:,
            job_state: @job_state.as_json,
            pull_request_states: @pull_request_states.as_json,
          }
        end

        sig { returns(T::Boolean) }
        def persisted? = @persisted
      end
    end
  end
end
