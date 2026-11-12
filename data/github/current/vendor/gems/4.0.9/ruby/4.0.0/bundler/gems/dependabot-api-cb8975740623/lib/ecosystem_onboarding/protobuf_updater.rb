# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

# Updates protobuf enum definitions for new ecosystems
class EcosystemOnboarding
  class ProtobufUpdater < BaseUpdater
    extend T::Sig

    sig { override.returns(T::Hash[Symbol, T::Array[String]]) }
    def update
      changes = []
      manual_steps = []

      proto_file = root_path.join("proto/dependabot-api/twirp/dependabot_api.proto")
      return { changes: changes, manual_steps: manual_steps } unless File.exist?(proto_file)

      change_desc = "Add #{protobuf_constant_name} to protobuf enum"
      return { changes: changes, manual_steps: manual_steps } unless should_proceed?(proto_file, change_desc)

      content = File.read(proto_file)

      return skip_if_exists(changes, manual_steps) if already_exists?(content)

      insert_protobuf_entry(proto_file, content, changes, manual_steps)

      { changes: changes, manual_steps: manual_steps }
    rescue StandardError => e
      Rails.logger.debug { "✗ Error updating protobuf: #{e.message}" }
      { changes: [], manual_steps: [] }
    end

    private

    sig do
      params(
        changes: T::Array[String],
        manual_steps: T::Array[String]
      ).returns(T::Hash[Symbol, T::Array[String]])
    end
    def skip_if_exists(changes, manual_steps)
      Rails.logger.debug { "⚠ #{protobuf_constant_name} already exists in protobuf enum, skipping" }
      { changes: changes, manual_steps: manual_steps }
    end

    sig do
      params(
        proto_file: Pathname,
        content: String,
        changes: T::Array[String],
        manual_steps: T::Array[String]
      ).void
    end
    def insert_protobuf_entry(proto_file, content, changes, manual_steps)
      next_id = calculate_next_id(content)
      if insert_enum_entry(proto_file, content, next_id)
        add_success_messages(changes, manual_steps, next_id)
      else
        Rails.logger.debug "✗ Could not find insertion point in protobuf file"
      end
    end

    sig { params(changes: T::Array[String], manual_steps: T::Array[String], next_id: Integer).void }
    def add_success_messages(changes, manual_steps, next_id)
      changes << "Added #{protobuf_constant_name} = #{next_id} to protobuf enum"
      manual_steps << "Run 'script/protoc' to regenerate Twirp Ruby code"
      manual_steps << "Bump gem version in gen/ruby/lib/proto/dependabot-api/version.rb"
      manual_steps << "Create PRs/releases for regenerated protobuf code"
      Rails.logger.debug { "✓ Added #{protobuf_constant_name} to protobuf enum with ID #{next_id}" }
    end

    sig { params(content: String).returns(T::Boolean) }
    def already_exists?(content)
      content.match?(/^\s+#{Regexp.escape(protobuf_constant_name)}\s+=/)
    end

    sig { params(content: String).returns(Integer) }
    def calculate_next_id(content)
      enum_entries = content.scan(/^\s+(\w+)\s+=\s+(\d+);/)
      last_id = enum_entries.map { |_, id| id.to_i }.max || 0
      last_id + 1
    end

    sig { params(proto_file: Pathname, content: String, next_id: Integer).returns(T::Boolean) }
    def insert_enum_entry(proto_file, content, next_id)
      return false unless content =~ /^(\s+\w+\s+=\s+\d+;\n)(\s+\})/

      new_entry = "    #{protobuf_constant_name} = #{next_id};\n"
      modified_content = content.sub(/^(\s+\w+\s+=\s+\d+;\n)(\s+\})/) do
        "#{Regexp.last_match(1)}#{new_entry}#{Regexp.last_match(2)}"
      end

      File.write(proto_file, modified_content)
      true
    end
  end
end
