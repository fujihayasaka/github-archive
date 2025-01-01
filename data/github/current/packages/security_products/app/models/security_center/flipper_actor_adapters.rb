# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module FlipperActorAdapters
    class Base
      extend T::Sig
      include GitHub::FlipperActor
      include GitHub::VexiActor

      sig { params(id: Integer).void }
      def initialize(id)
        @id = id
      end

      sig { override.returns(String) }
      def flipper_id
        "#{self.class.name&.demodulize}:#{@id}"
      end

      sig { override.returns(String) }
      def vexi_id
        flipper_id
      end
    end

    class Repository < Base; end
    class Organization < Base; end
    class Business < Base; end
  end
end
