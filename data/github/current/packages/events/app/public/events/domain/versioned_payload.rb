# typed: strict
# frozen_string_literal: true

module Events
  class Domain
    class VersionedPayload
      sig { returns(T::Hash[Symbol, T.anything]) }
      attr_reader :payload

      sig do
        params(
          version: String,
          init_payload: T::Hash[Symbol, T.anything],
          blk: T.nilable(T.proc.params(arg0: Events::Domain::VersionedPayload).void)
        )
        .void
      end
      def initialize(version, init_payload = {}, &blk)
        @requested_version_raw = version
        @payload = init_payload
        yield self if block_given?
      end

      sig do
        params(
          key: Symbol,
          serialize_method: Symbol,
          obj: T.anything, options: T::Hash[Symbol, T.anything]
        )
        .void
      end
      def serialize(key, serialize_method, obj, options = {})
        return unless self.is_valid?
        options.merge!({ api_version: self.selected_version })
        @payload[key] = Api::Serializer.serialize(serialize_method, obj, { serialize_login: :display }.merge(options))
      end

      sig { returns(T::Boolean) }
      def is_valid?
        @is_valid ||= T.let(Api::Versioning.usable_version?(@requested_version_raw), T.nilable(T::Boolean))
      end

      sig { returns(T.nilable(Api::SelectedVersion)) }
      def selected_version
        # We use Api::SelectedVersion::REASON_PINNED here because it was decided that only valid payload versions will
        # be accepted by this endpoint. We will not set a default version as a graceful fallback if the version requested
        # is invalid. The appropriate reason to use therefore is Api::SelectedVersion::REASON_PINNED
        @selected_version ||= T.let(
          Api::SelectedVersion.new(@requested_version_raw, @requested_version_raw, Api::SelectedVersion::REASON_PINNED),
          T.nilable(Api::SelectedVersion))
      end

      sig { returns(T::Hash[Symbol, T.anything]) }
      def to_h # rubocop:disable Metrics/MethodLength
        if is_valid?
          {
            version: @requested_version_raw,
            payload: @payload.to_json,
            code: :RESULT_CODE_SUCCESS
          }
        else
          {
            version: @requested_version_raw,
            payload: nil,
            code: :RESULT_CODE_INVALID_VERSION
          }
        end
      end
    end
  end
end
