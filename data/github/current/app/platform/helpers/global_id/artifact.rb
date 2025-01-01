# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Helpers
    module GlobalId
      module Artifact
        class BreakingChangeError < StandardError; end

        # Unless `BREAKING_CHANGES=...` is present in ENV, this method will raise an error if it detects a breaking change.
        # @param path_to_artifact [String] A path to a file containing the previous YAML for this metadata
        # @return void
        def self.update_artifact(path_to_artifact)
          old_contents = File.read(path_to_artifact)
          old_metadata = YAML.load(old_contents)
          new_metadata = generate_metadata
          if !ENV["BREAKING_CHANGES"]
            check_for_breaking_changes(old_metadata, new_metadata)
          end
          # If that ^^ doesn't raise, we're good to go
          File.write(path_to_artifact, YAML.dump(new_metadata))
          nil
        end

        def self.check_for_breaking_changes(old_metadata, new_metadata)
          old_metadata.each do |prefix, old_type_metadata|
            new_type_metadata = new_metadata[prefix]
            if new_type_metadata.nil?
              raise BreakingChangeError, <<~ERR
                #{prefix.inspect} has been removed from GlobalId metadata, which will break ID parsing.

                Without this prefix, some previously-created IDs will fail to parse when sent to the server.

                To override this error, re-run the script with `BREAKING_CHANGES=1`
              ERR
            end

            if old_type_metadata.fetch("type") != new_type_metadata.fetch("type")
              raise BreakingChangeError, <<~ERR
              #{prefix.inspect} has a new type (previous: #{old_type_metadata["type"].inspect}, new: #{new_type_metadata["type"].inspect}).
              This will cause existing IDs to be parsed using a different GraphQL type definition, which may break the lookup.

              Revert this change to maintain compatibility with existing IDs.

              To override this error, re-run the script with `BREAKING_CHANGES=1`
              ERR
            end

            if old_type_metadata.fetch("ready") != new_type_metadata.fetch("ready")
              raise BreakingChangeError, <<~ERR
              #{prefix.inspect}'s \"ready\" date has changed (previous: #{old_type_metadata["ready"].inspect}, new: #{new_type_metadata["ready"].inspect}).

              If this date changes, then objects created on GitHub.com _between_ those two dates will start returning different IDs, breaking clients who saved the old ID.
              (This is OK if both dates are in the future.)

              To override this error, re-run the script with `BREAKING_CHANGES=1`
              ERR
            end

            old_type_metadata.fetch("templates").each do |old_idx, old_template|
              new_template = new_type_metadata.fetch("templates")[old_idx]
              if new_template != old_template
                raise BreakingChangeError, <<~ERR
                #{prefix}.templates[#{old_idx}] has changes. This will cause previously-created IDs to be wrongly parsed by the server,
                and it will cause some object to generate _different_ IDs than they generated before.

                - Previous template: #{old_template.inspect}
                - New template: #{new_template.inspect}

                Make sure that these templates don't change, so that we don't break the API.

                To override this error, re-run the script with `BREAKING_CHANGES=1`
                ERR
              end
            end
          end
        end

        # @param except [Array<String>] A list of short names to exclude from the generated YAML
        # @return [Hash] A sorted Hash of Global ID structure metadata
        def self.generate_metadata(except: [])
          Platform::Schema # force all GraphQL types to be autoloaded

          sorted_keys = EXPAND_TYPE_NAMES.keys.sort
          sorted_keys -= except
          sorted_hash = {}
          sorted_keys.each do |k|
            type_name = EXPAND_TYPE_NAMES[k]
            templates = {}
            type_defn = Platform::Schema.get_type(type_name) || raise("Invariant: Type not found for prefix: #{k.inspect}, type name: #{type_name.inspect}") # rubocop:disable GitHub/UsePlatformErrors
            type_defn.global_id_templates.each_with_index do |template, idx|
              templates[idx] = template.inspect
            end

            sorted_hash[k] = { "type" => type_name, "ready" => type_defn.global_id_ready_date&.strftime("%Y-%m-%d") || "nil", "templates" => templates }
          end
          sorted_hash
        end
      end
    end
  end
end
