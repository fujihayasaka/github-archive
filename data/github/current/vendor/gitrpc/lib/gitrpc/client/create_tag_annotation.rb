# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  # Simple wrapper around request to GitRPC::Backend.create_tag_annotation.
  #
  # tag_name   - String Tag name
  # target_oid - String Target object ID
  # message    - String Tag message
  # tagger     - Hash Information about the tagger and the timestamp containing
  #              :name  - Name of the tagger
  #              :email - Email address of the tagger
  #              :time  - Timestamp of the tag to be created
  #
  # Returns the OID of the annotated tag that was created, or raises
  # GitRPC::CommandFailed.
  class Client
    def create_tag_annotation(tag_name, target_oid, message:, tagger:)
      time = tagger.fetch(:time)
      time = time.respond_to?(:iso8601) ? time.iso8601 : time
      send_message(:create_tag_annotation, tag_name, target_oid, {
        "message" => message,
        "tagger" => {
          "name"  => tagger.fetch(:name),
          "email" => tagger.fetch(:email),
          "time"  => time,
        }
      })
    end
  end
end
