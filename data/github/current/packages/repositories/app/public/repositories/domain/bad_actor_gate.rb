# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    module BadActorGate
      extend T::Sig

      include Kernel

      module Error
        class UnprocessableEntity < StandardError
          extend T::Sig

          MESSAGE = T.let(<<~MSG, String)
            This request cannot be processed based on the number of associated repositories. For more information, see
            #{GitHub.help_url}/repositories/creating-and-managing-repositories/repository-limits#organization-limits
          MSG

          sig { params(msg: String).void }
          def initialize(msg = MESSAGE)
            super
          end
        end
      end

      class DomainMethodActor
        include GitHub::FlipperActor
        include GitHub::VexiActor

        extend T::Sig

        sig { params(domain_name: String, method_name: Symbol, actor_id: Integer, owner_id: Integer).void }
        def initialize(domain_name, method_name, actor_id, owner_id)
          @domain_name = domain_name
          @method_name = method_name
          @actor_id = actor_id
          @owner_id = owner_id
        end

        sig { override.returns(String) }
        def flipper_id

          "#{@domain_name}::Owner:#{@owner_id}::Actor:#{@actor_id}::#{@method_name}"
        end

        sig { override.returns(String) }
        def vexi_id
          flipper_id
        end
      end

      protected

      sig { params(owner_id: Integer, method_name: Symbol).void }
      def check_domain_bad_actor_gate!(owner_id:, method_name:)
        raise Error::UnprocessableEntity if gate_closed_on?(owner_id:, method_name:)
      end

      sig { params(owner_id: Integer, method_name: Symbol).returns(T::Boolean) }
      def gate_closed_on?(owner_id:, method_name:)
        actor = T.cast(self, GH::Domain::Base).actor
        return false if actor.nil? || actor.id.nil?

        domain_name = self.class.name
        domain_method_actor = DomainMethodActor.new(domain_name, method_name, T.must(actor.id), owner_id)
        return false unless method_actor_gate_closed_for?(domain_method_actor)

        emit_telemetry(method_name:, owner_id:)
        true
      end

      private

      sig { params(domain_method_actor: DomainMethodActor).returns(T::Boolean) }
      def method_actor_gate_closed_for?(domain_method_actor)
        # This is a no-op if the feature flag is dark shipped
        # We don't want to risk accidentally enabling the gate for all actors
        return false if GitHub.flipper[:repos_domain_bad_actor_gate].enabled? || GitHub.flipper[:repos_domain_bad_actor_gate].percentage_of_time_value.to_i > 0

        GitHub.flipper[:repos_domain_bad_actor_gate].enabled?(domain_method_actor) # rubocop:disable GitHub/UseActorFeatureEnabled
      end

      sig { params(method_name: Symbol, owner_id: Integer).void }
      def emit_telemetry(method_name:, owner_id:)
        actor = T.cast(self, GH::Domain::Base).actor
        domain_name = self.class.name
        GitHub.dogstats.increment("domain.bad_actor_gate", tags: ["domain:#{domain_name}", "method:#{method_name}"])
        GitHub.logger.info(
          "Bad actor gate closed",
          "code.namespace" => domain_name,
          "code.function" => method_name,
          "gh.actor.id" => T.must(actor&.id),
          "gh.owner.id" => owner_id,
          "gh.request_id" => GitHub.context[:request_id]
        )
      end
    end
  end
end
