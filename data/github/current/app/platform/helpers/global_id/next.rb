# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module GlobalId
      class Next
        def self.parse(unparsed_id)
          if unparsed_id.include?('"')
            # For historical reasons, we apparently support IDs wrapped in quotes?
            unparsed_id = unparsed_id.sub(/\A"/, "").sub(/"\Z/, "")
          end

          stripped_gid = unparsed_id.split(GlobalId::DELIMITER, 2)
          if stripped_gid.length != 2
            # It's garbage
            return
          else
            begin
              type_hint, id_part = stripped_gid
              id_part.strip!
              decoded_packed_path = Base64.urlsafe_decode64(id_part)
              decoded_path_parts = MessagePack.unpack(decoded_packed_path)

              type = GlobalId.expand_type_name(type_hint)
              template_index = decoded_path_parts[0]

              keys = Platform::Schema.get_type(type).global_id_templates[template_index]

              parts = {}
              keys.each_with_index do |key, i|
                if i == 0
                  parts[:prefix] = key
                else
                  parts[key] = decoded_path_parts[i]
                end
              end
            rescue ArgumentError, MessagePack::MalformedFormatError, EOFError
              malformed = true
            end
          end

          unless type.present? && /\A[a-zA-Z0-9_]+\Z/.match(type) && !T.must(parts).empty?
            raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of '#{unparsed_id}'"
          end

          if malformed
            GitHub.dogstats.increment("platform.malformed_id")
          end

          new(parts, type)
        end

        attr_reader :id, :parts, :type

        def initialize(parts, type)
          @parts = parts
          @type  = type
          @id    = @parts.values.last # Actions currently depends on the objects id being the last element in the array
        end
      end
    end
  end
end
